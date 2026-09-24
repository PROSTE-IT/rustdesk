//! Background inventory, health and update agent for managed Windows Helpdesk builds.
//!
//! It runs in the installed RustDesk service, independently from any interactive
//! user or technician session.  The per-installation credential is distinct from
//! technician credentials and is encrypted with RustDesk's machine-bound config
//! encryption before it is persisted.

use hbb_common::{
    config::{self, Config},
    log,
    password_security::{decrypt_str_or_original, encrypt_str_or_original},
    sysinfo::{Disks, System},
};
use reqwest::blocking::Client;
use serde::Deserialize;
use serde_json::{json, Map, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeSet,
    process::Command,
    sync::Once,
    thread,
    time::{Duration, Instant},
};
use uuid::Uuid;
use winreg::{enums::*, RegKey};

const INSTALLATION_ID_OPTION: &str = "rdbk-host-installation-id";
const TOKEN_OPTION: &str = "rdbk-host-token";
const TOKEN_ENCRYPTION_VERSION: &str = "00";
const TOKEN_MAX_LEN: usize = 512;
const DEFAULT_HEARTBEAT_SECONDS: u64 = 300;
const SAMPLE_SECONDS: u64 = 60;
const DISCOVERY_SECONDS: u64 = 30 * 60;
const UPDATE_CHECK_SECONDS: u64 = 6 * 60 * 60;

static START: Once = Once::new();

#[derive(Debug, Deserialize)]
struct RegistrationResponse {
    token: String,
    #[serde(default = "default_heartbeat_seconds")]
    heartbeat_seconds: u64,
}

#[derive(Debug, Deserialize)]
struct HeartbeatResponse {
    #[serde(default)]
    update_check_url: String,
    #[serde(default = "default_heartbeat_seconds")]
    next_heartbeat_seconds: u64,
}

#[derive(Debug, Deserialize)]
struct UpdateResponse {
    #[serde(default)]
    configured: bool,
    #[serde(default)]
    auto_update: bool,
    #[serde(default)]
    version: String,
    #[serde(default)]
    build_uuid: String,
    #[serde(default)]
    download_url: String,
}

fn default_heartbeat_seconds() -> u64 {
    DEFAULT_HEARTBEAT_SECONDS
}

#[derive(Default)]
struct MetricWindow {
    count: u32,
    cpu_sum: f64,
    cpu_max: f64,
    memory_sum: f64,
    memory_max: f64,
    disks: Vec<Value>,
}

impl MetricWindow {
    fn sample(&mut self, system: &mut System, disks: &mut Disks) {
        system.refresh_cpu();
        system.refresh_memory();
        disks.refresh_list();
        disks.refresh();

        let cpu = system.global_cpu_info().cpu_usage().clamp(0.0, 100.0) as f64;
        let total_memory = system.total_memory();
        let memory = if total_memory > 0 {
            (system.used_memory() as f64 / total_memory as f64 * 100.0).clamp(0.0, 100.0)
        } else {
            0.0
        };
        self.count += 1;
        self.cpu_sum += cpu;
        self.cpu_max = self.cpu_max.max(cpu);
        self.memory_sum += memory;
        self.memory_max = self.memory_max.max(memory);
        self.disks = disks
            .list()
            .iter()
            .filter_map(|disk| {
                let total = disk.total_space();
                if total == 0 {
                    return None;
                }
                let free = disk.available_space().min(total);
                let used_percent = (100.0 - free as f64 / total as f64 * 100.0).clamp(0.0, 100.0);
                Some(json!({
                    "name": disk.mount_point().to_string_lossy(),
                    "total_bytes": total,
                    "free_bytes": free,
                    "used_percent": round_two(used_percent),
                }))
            })
            .collect();
    }

    fn to_json(&self) -> Option<Value> {
        if self.count == 0 {
            return None;
        }
        let count = self.count as f64;
        let value = json!({
            "period_seconds": (self.count as u64 * SAMPLE_SECONDS).clamp(30, 900),
            "cpu_average_percent": round_two(self.cpu_sum / count),
            "cpu_maximum_percent": round_two(self.cpu_max),
            "memory_average_percent": round_two(self.memory_sum / count),
            "memory_maximum_percent": round_two(self.memory_max),
            "disks": self.disks,
        });
        Some(value)
    }

    fn clear(&mut self) {
        *self = Self::default();
    }
}

pub fn start() {
    if option_env!("RDBK_HOST_AGENT").unwrap_or("") != "true"
        || option_env!("RDBK_UPDATE_CHANNEL").unwrap_or("") != "windows_helpdesk"
        || option_env!("RDBK_API_URL").unwrap_or("").trim().is_empty()
        || option_env!("RDBK_HOST_REGISTRATION_SECRET")
            .unwrap_or("")
            .trim()
            .is_empty()
    {
        return;
    }
    START.call_once(|| {
        thread::spawn(|| {
            if let Err(error) = run() {
                log::error!("RDBK host agent stopped: {error}");
            }
        });
    });
}

fn run() -> hbb_common::ResultType<()> {
    let base_url = option_env!("RDBK_API_URL")
        .unwrap_or("")
        .trim_end_matches('/')
        .to_owned();
    let client = Client::builder()
        .connect_timeout(Duration::from_secs(10))
        .timeout(Duration::from_secs(45))
        .redirect(reqwest::redirect::Policy::none())
        .user_agent(format!("PROSTE-IT-RustDesk-Host/{}", current_version()))
        .build()?;
    let mut installation_id = installation_id();
    let mut token = load_token();
    let mut heartbeat_seconds = DEFAULT_HEARTBEAT_SECONDS;
    let mut metrics = MetricWindow::default();
    let mut system = System::new_all();
    let mut disks = Disks::new_with_refreshed_list();
    let mut next_sample = Instant::now();
    let mut next_heartbeat = Instant::now();
    let mut next_discovery = Instant::now();
    let mut next_update_check = Instant::now();

    loop {
        let now = Instant::now();
        if now >= next_sample {
            metrics.sample(&mut system, &mut disks);
            next_sample = now + Duration::from_secs(SAMPLE_SECONDS);
        }

        if now >= next_discovery {
            if let Err(error) = crate::lan::discover() {
                log::debug!("RDBK LAN discovery failed: {error}");
            }
            next_discovery = Instant::now() + Duration::from_secs(DISCOVERY_SECONDS);
        }

        if now >= next_heartbeat {
            if token.is_empty() {
                match register(&client, &base_url, &installation_id) {
                    Ok(response) => {
                        token = response.token;
                        store_token(&token);
                        heartbeat_seconds = bounded_interval(response.heartbeat_seconds);
                    }
                    Err(RegisterError::Duplicate) => {
                        installation_id = Uuid::new_v4().to_string();
                        Config::set_option(
                            INSTALLATION_ID_OPTION.to_owned(),
                            installation_id.clone(),
                        );
                        log::warn!(
                            "RDBK host identity was duplicated; generated a replacement identity"
                        );
                        thread::sleep(Duration::from_secs(5));
                        continue;
                    }
                    Err(RegisterError::Temporary(error)) => {
                        log::warn!("RDBK host registration failed: {error}");
                        next_heartbeat = Instant::now() + Duration::from_secs(60);
                        thread::sleep(Duration::from_secs(1));
                        continue;
                    }
                }
            }

            let payload = heartbeat_payload(&system, metrics.to_json());
            match send_heartbeat(&client, &base_url, &token, payload) {
                Ok(response) => {
                    metrics.clear();
                    heartbeat_seconds = bounded_interval(response.next_heartbeat_seconds);
                    if !response.update_check_url.is_empty() && now >= next_update_check {
                        if let Err(error) =
                            check_managed_update(&client, &response.update_check_url)
                        {
                            log::warn!("RDBK managed update check failed: {error}");
                        }
                        next_update_check =
                            Instant::now() + Duration::from_secs(UPDATE_CHECK_SECONDS);
                    }
                }
                Err(HeartbeatError::Unauthorized) => {
                    log::warn!("RDBK host token was rejected; registering a new host identity");
                    token.clear();
                    store_token("");
                    next_heartbeat = Instant::now() + Duration::from_secs(5);
                    continue;
                }
                Err(HeartbeatError::Temporary(error)) => {
                    log::warn!("RDBK host heartbeat failed: {error}");
                }
            }
            next_heartbeat = Instant::now() + Duration::from_secs(heartbeat_seconds);
        }

        let until_sample = next_sample.saturating_duration_since(Instant::now());
        let until_heartbeat = next_heartbeat.saturating_duration_since(Instant::now());
        thread::sleep(
            until_sample
                .min(until_heartbeat)
                .min(Duration::from_secs(5)),
        );
    }
}

enum RegisterError {
    Duplicate,
    Temporary(String),
}

fn register(
    client: &Client,
    base_url: &str,
    installation_id: &str,
) -> Result<RegistrationResponse, RegisterError> {
    let rustdesk_id = Config::get_id();
    if rustdesk_id.is_empty() {
        return Err(RegisterError::Temporary(
            "RustDesk ID is not ready".to_owned(),
        ));
    }
    let response = client
        .post(format!("{base_url}/api/v1/host/register/"))
        .header(
            "X-RDBK-Registration-Secret",
            option_env!("RDBK_HOST_REGISTRATION_SECRET").unwrap_or(""),
        )
        .json(&json!({
            "installation_id": installation_id,
            "rustdesk_id": rustdesk_id,
            "client_version": current_version(),
            "update_channel": "windows_helpdesk",
        }))
        .send()
        .map_err(|error| RegisterError::Temporary(error.to_string()))?;
    if response.status().as_u16() == 409 {
        return Err(RegisterError::Duplicate);
    }
    if !response.status().is_success() {
        return Err(RegisterError::Temporary(format!(
            "HTTP {}",
            response.status()
        )));
    }
    response
        .json()
        .map_err(|error| RegisterError::Temporary(error.to_string()))
}

enum HeartbeatError {
    Unauthorized,
    Temporary(String),
}

fn send_heartbeat(
    client: &Client,
    base_url: &str,
    token: &str,
    payload: Value,
) -> Result<HeartbeatResponse, HeartbeatError> {
    let response = client
        .post(format!("{base_url}/api/v1/host/heartbeat/"))
        .header("Authorization", format!("Host {token}"))
        .json(&payload)
        .send()
        .map_err(|error| HeartbeatError::Temporary(error.to_string()))?;
    if matches!(response.status().as_u16(), 401 | 403) {
        return Err(HeartbeatError::Unauthorized);
    }
    if !response.status().is_success() {
        return Err(HeartbeatError::Temporary(format!(
            "HTTP {}",
            response.status()
        )));
    }
    response
        .json()
        .map_err(|error| HeartbeatError::Temporary(error.to_string()))
}

fn heartbeat_payload(system: &System, metrics: Option<Value>) -> Value {
    let os = windows_os();
    let identity = active_identity();
    let mut payload = Map::new();
    payload.insert("rustdesk_id".to_owned(), json!(Config::get_id()));
    payload.insert("client_version".to_owned(), json!(current_version()));
    payload.insert("hostname".to_owned(), json!(crate::common::hostname()));
    payload.insert("os_name".to_owned(), json!(os.0));
    payload.insert("os_version".to_owned(), json!(os.1));
    payload.insert("architecture".to_owned(), json!(std::env::consts::ARCH));
    payload.insert("is_server".to_owned(), json!(is_windows_server()));
    payload.insert(
        "is_installed".to_owned(),
        json!(crate::platform::is_installed()),
    );
    payload.insert(
        "cpu_name".to_owned(),
        json!(system
            .cpus()
            .first()
            .map(|cpu| cpu.brand().trim())
            .unwrap_or("")),
    );
    payload.insert(
        "cpu_logical_count".to_owned(),
        json!(system.cpus().len().max(1)),
    );
    payload.insert(
        "memory_total_bytes".to_owned(),
        json!(system.total_memory()),
    );
    payload.insert(
        "hardware_fingerprint".to_owned(),
        json!(hardware_fingerprint()),
    );
    payload.insert("local_ip_addresses".to_owned(), json!(local_ip_addresses()));
    payload.insert("entra_tenant_id".to_owned(), json!(entra_tenant_id()));
    payload.insert("ad_domain_name".to_owned(), json!(ad_domain_name()));
    payload.insert("ad_domain_sid".to_owned(), json!(ad_domain_sid()));
    payload.insert("email_domains".to_owned(), json!(email_domains()));
    payload.insert(
        "network_fingerprint".to_owned(),
        json!(network_fingerprint()),
    );
    payload.insert(
        "nearby_rustdesk_ids".to_owned(),
        json!(nearby_rustdesk_ids()),
    );
    payload.insert("pending_reboot".to_owned(), json!(pending_reboot()));
    if let Some(identity) = identity {
        payload.insert("identity".to_owned(), identity);
    }
    if let Some(event) = latest_critical_event() {
        payload.insert("critical_event".to_owned(), event);
    }
    if let Some(metrics) = metrics {
        payload.insert("metrics".to_owned(), metrics);
    }
    Value::Object(payload)
}

fn check_managed_update(client: &Client, url: &str) -> hbb_common::ResultType<()> {
    let response = client.get(url).send()?;
    if !response.status().is_success() {
        hbb_common::bail!("HTTP {}", response.status());
    }
    let update: UpdateResponse = response.json()?;
    if !update.configured
        || !update.auto_update
        || update.download_url.is_empty()
        || update.build_uuid.is_empty()
        || update.build_uuid == option_env!("RDBK_BUILD_UUID").unwrap_or("")
        || !is_newer_managed_version(&update.version, current_version())
    {
        return Ok(());
    }
    crate::updater::install_support_update(update.download_url)
}

fn current_version() -> &'static str {
    let managed = option_env!("PIT_VERSION").unwrap_or("").trim();
    if managed.is_empty() {
        crate::VERSION
    } else {
        managed
    }
}

fn managed_version_key(value: &str) -> ([u64; 4], u64) {
    let (base, suffix) = value.trim().split_once('-').unwrap_or((value.trim(), ""));
    let mut numbers = [0_u64; 4];
    for (index, part) in base.split('.').take(numbers.len()).enumerate() {
        numbers[index] = part.parse().unwrap_or(0);
    }
    let revision = suffix
        .strip_prefix("pit.")
        .unwrap_or(suffix)
        .parse()
        .unwrap_or(0);
    (numbers, revision)
}

fn is_newer_managed_version(candidate: &str, current: &str) -> bool {
    managed_version_key(candidate) > managed_version_key(current)
}

fn installation_id() -> String {
    let current = Config::get_option(INSTALLATION_ID_OPTION);
    if Uuid::parse_str(&current).is_ok() {
        return current;
    }
    let generated = Uuid::new_v4().to_string();
    Config::set_option(INSTALLATION_ID_OPTION.to_owned(), generated.clone());
    generated
}

fn load_token() -> String {
    let stored = Config::get_option(TOKEN_OPTION);
    let (token, decrypted, should_store) =
        decrypt_str_or_original(&stored, TOKEN_ENCRYPTION_VERSION);
    if token.is_empty() || token.starts_with("rdbk_host_") {
        if !token.is_empty() && !decrypted && should_store {
            store_token(&token);
        }
        return token;
    }
    if !stored.is_empty() {
        log::warn!("RDBK host token could not be decrypted");
    }
    String::new()
}

fn store_token(token: &str) {
    let stored = if token.is_empty() {
        String::new()
    } else {
        encrypt_str_or_original(token, TOKEN_ENCRYPTION_VERSION, TOKEN_MAX_LEN)
    };
    Config::set_option(TOKEN_OPTION.to_owned(), stored);
}

fn bounded_interval(value: u64) -> u64 {
    value.clamp(60, 30 * 60)
}

fn round_two(value: f64) -> f64 {
    (value * 100.0).round() / 100.0
}

fn registry_string(path: &str, name: &str) -> String {
    RegKey::predef(HKEY_LOCAL_MACHINE)
        .open_subkey_with_flags(path, KEY_READ | KEY_WOW64_64KEY)
        .ok()
        .and_then(|key| key.get_value::<String, _>(name).ok())
        .unwrap_or_default()
        .trim()
        .to_owned()
}

fn windows_os() -> (String, String) {
    let path = r"SOFTWARE\Microsoft\Windows NT\CurrentVersion";
    let product = registry_string(path, "ProductName");
    let display = registry_string(path, "DisplayVersion");
    let build = registry_string(path, "CurrentBuildNumber");
    let version = [display, build]
        .into_iter()
        .filter(|value| !value.is_empty())
        .collect::<Vec<_>>()
        .join(" / ");
    (product, version)
}

fn is_windows_server() -> bool {
    let product_type = registry_string(
        r"SYSTEM\CurrentControlSet\Control\ProductOptions",
        "ProductType",
    );
    !product_type.is_empty() && !product_type.eq_ignore_ascii_case("WinNT")
}

fn hardware_fingerprint() -> String {
    let machine_guid = registry_string(r"SOFTWARE\Microsoft\Cryptography", "MachineGuid");
    hash_identifier(&machine_guid)
}

fn entra_join_values() -> (String, Vec<String>) {
    let root = RegKey::predef(HKEY_LOCAL_MACHINE);
    let Ok(join_info) = root.open_subkey_with_flags(
        r"SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo",
        KEY_READ | KEY_WOW64_64KEY,
    ) else {
        return Default::default();
    };
    for key_name in join_info.enum_keys().flatten() {
        if let Ok(key) = join_info.open_subkey_with_flags(key_name, KEY_READ | KEY_WOW64_64KEY) {
            let tenant = key.get_value::<String, _>("TenantId").unwrap_or_default();
            let email = key.get_value::<String, _>("UserEmail").unwrap_or_default();
            if !tenant.trim().is_empty() {
                return (tenant.trim().to_owned(), vec![email]);
            }
        }
    }
    Default::default()
}

fn entra_tenant_id() -> String {
    entra_join_values().0
}

fn ad_domain_name() -> String {
    registry_string(
        r"SYSTEM\CurrentControlSet\Services\Tcpip\Parameters",
        "Domain",
    )
}

fn ad_domain_sid() -> String {
    powershell_output(
        "$c=Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue; if($c.PartOfDomain){$s=(Get-CimInstance Win32_UserAccount -Filter \"LocalAccount=False\" -ErrorAction SilentlyContinue|Where-Object {$_.Domain -eq $c.Domain -and $_.SID}|Select-Object -First 1 -ExpandProperty SID);if($s){$s.Substring(0,$s.LastIndexOf('-'))}}",
    )
    .lines()
    .next()
    .unwrap_or("")
    .trim()
    .to_owned()
}

fn email_domains() -> Vec<String> {
    let mut emails = entra_join_values().1;
    let office = powershell_output(
        "$o=Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue|ForEach-Object {Get-ChildItem ($_.PSPath+'\\Software\\Microsoft\\Office\\16.0\\Common\\Identity\\Identities') -ErrorAction SilentlyContinue|ForEach-Object {(Get-ItemProperty $_.PSPath -Name EmailAddress -ErrorAction SilentlyContinue).EmailAddress}};$t=Get-ChildItem ($env:SystemDrive+'\\Users\\*\\AppData\\Roaming\\Thunderbird\\Profiles\\*\\prefs.js') -ErrorAction SilentlyContinue|Select-String -Pattern 'mail\\.identity\\.[^.]+\\.useremail\",\\s*\"([^\"]+)' -AllMatches|ForEach-Object {$_.Matches|ForEach-Object {$_.Groups[1].Value}};@($o)+@($t)",
    );
    emails.extend(office.lines().map(str::to_owned));
    emails
        .into_iter()
        .filter_map(|email| {
            email
                .rsplit_once('@')
                .map(|(_, domain)| domain.trim().to_lowercase())
        })
        .filter(|domain| !domain.is_empty() && domain.contains('.'))
        .collect::<BTreeSet<_>>()
        .into_iter()
        .take(16)
        .collect()
}

fn active_identity() -> Option<Value> {
    let username = crate::platform::get_active_username();
    if username.is_empty() || username.eq_ignore_ascii_case("SYSTEM") {
        return None;
    }
    let display_name = powershell_output(
        "$c=Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue;$u=$c.UserName;if($u){$n=$u.Split('\\')[-1];(Get-CimInstance Win32_UserAccount -Filter \"Name='$n'\" -ErrorAction SilentlyContinue|Select-Object -First 1 -ExpandProperty FullName)}",
    )
    .lines()
    .next()
    .unwrap_or("")
    .trim()
    .to_owned();
    Some(json!({
        "username": username,
        "display_name": display_name,
        "source": "windows",
    }))
}

fn network_fingerprint() -> String {
    let gateway = powershell_output(
        "$r=Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue|Where-Object {$_.NextHop -ne '0.0.0.0'}|Sort-Object RouteMetric|Select-Object -First 1;if($r){$n=Get-NetNeighbor -InterfaceIndex $r.InterfaceIndex -IPAddress $r.NextHop -ErrorAction SilentlyContinue|Select-Object -First 1;if($n){$n.LinkLayerAddress+'|'+$r.NextHop}}",
    );
    hash_identifier(gateway.trim())
}

fn local_ip_addresses() -> Vec<String> {
    let mut ipv4 = BTreeSet::new();
    let mut ipv6 = BTreeSet::new();
    for interface in default_net::get_interfaces() {
        for network in interface.ipv4 {
            let address = network.addr;
            if !address.is_loopback()
                && !address.is_unspecified()
                && !address.is_multicast()
                && !address.is_broadcast()
            {
                ipv4.insert(address.to_string());
            }
        }
        for network in interface.ipv6 {
            let address = network.addr;
            if !address.is_loopback()
                && !address.is_unspecified()
                && !address.is_multicast()
                && !address.is_unicast_link_local()
            {
                ipv6.insert(address.to_string());
            }
        }
    }
    ipv4.into_iter().chain(ipv6).take(32).collect()
}

fn nearby_rustdesk_ids() -> Vec<String> {
    config::LanPeers::load()
        .peers
        .into_iter()
        .filter(|peer| peer.online && peer.id.chars().all(|c| c.is_ascii_digit()))
        .map(|peer| peer.id)
        .take(500)
        .collect()
}

fn pending_reboot() -> bool {
    let hklm = RegKey::predef(HKEY_LOCAL_MACHINE);
    for path in [
        r"SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        r"SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
    ] {
        if hklm
            .open_subkey_with_flags(path, KEY_READ | KEY_WOW64_64KEY)
            .is_ok()
        {
            return true;
        }
    }
    hklm.open_subkey_with_flags(
        r"SYSTEM\CurrentControlSet\Control\Session Manager",
        KEY_READ | KEY_WOW64_64KEY,
    )
    .ok()
    .and_then(|key| key.get_raw_value("PendingFileRenameOperations").ok())
    .is_some()
}

fn latest_critical_event() -> Option<Value> {
    let raw = powershell_output(
        "$e=Get-WinEvent -FilterHashtable @{LogName=@('System','Application');Level=1} -MaxEvents 10 -ErrorAction SilentlyContinue|Sort-Object TimeCreated -Descending|Select-Object -First 1;if($e){[pscustomobject]@{occurred_at=$e.TimeCreated.ToUniversalTime().ToString('o');source=$e.ProviderName;event_id=$e.Id}|ConvertTo-Json -Compress}",
    );
    serde_json::from_str(raw.trim()).ok()
}

fn powershell_output(script: &str) -> String {
    let system_root = std::env::var_os("SystemRoot").unwrap_or_else(|| "C:\\Windows".into());
    let executable = std::path::PathBuf::from(system_root)
        .join("System32")
        .join("WindowsPowerShell")
        .join("v1.0")
        .join("powershell.exe");
    Command::new(executable)
        .args([
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            script,
        ])
        .output()
        .ok()
        .filter(|output| output.status.success())
        .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_owned())
        .unwrap_or_default()
}

fn hash_identifier(value: &str) -> String {
    if value.trim().is_empty() {
        return String::new();
    }
    let mut hasher = Sha256::new();
    hasher.update(b"proste-it-rdbk-v1\0");
    hasher.update(value.trim().to_lowercase().as_bytes());
    hex::encode(hasher.finalize())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bounded_server_interval_is_safe() {
        assert_eq!(bounded_interval(1), 60);
        assert_eq!(bounded_interval(300), 300);
        assert_eq!(bounded_interval(99_999), 1800);
    }

    #[test]
    fn identifiers_are_not_sent_in_plain_text() {
        let value = hash_identifier("AA-BB-CC-DD-EE-FF|192.0.2.1");
        assert_eq!(value.len(), 64);
        assert!(!value.contains("aa-bb"));
    }

    #[test]
    fn managed_versions_compare_pit_revisions_numerically() {
        assert!(is_newer_managed_version("1.4.9-pit.20", "1.4.9-pit.9"));
        assert!(is_newer_managed_version("1.5.0-pit.1", "1.4.9-pit.99"));
        assert!(!is_newer_managed_version("1.4.9-pit.9", "1.4.9-pit.20"));
        assert!(!is_newer_managed_version("1.4.9", "1.4.9-pit.1"));
    }
}
