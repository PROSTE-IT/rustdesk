use crate::{common::do_check_software_update, hbbs_http::create_http_client_with_url};
use hbb_common::{bail, config, log, ResultType};
use std::{
    io::{Read, Write},
    path::PathBuf,
    sync::{
        atomic::{AtomicUsize, Ordering},
        mpsc::{channel, Receiver, Sender},
        Mutex,
    },
    time::{Duration, Instant},
};

#[cfg(target_os = "windows")]
const SUPPORT_UPDATE_MAX_BYTES: u64 = 200 * 1024 * 1024;

enum UpdateMsg {
    CheckUpdate,
    Exit,
}

lazy_static::lazy_static! {
    static ref TX_MSG : Mutex<Sender<UpdateMsg>> = Mutex::new(start_auto_update_check());
}

static CONTROLLING_SESSION_COUNT: AtomicUsize = AtomicUsize::new(0);

const DUR_ONE_DAY: Duration = Duration::from_secs(60 * 60 * 24);

pub fn update_controlling_session_count(count: usize) {
    CONTROLLING_SESSION_COUNT.store(count, Ordering::SeqCst);
}

#[allow(dead_code)]
pub fn start_auto_update() {
    let _sender = TX_MSG.lock().unwrap();
}

#[allow(dead_code)]
pub fn manually_check_update() -> ResultType<()> {
    let sender = TX_MSG.lock().unwrap();
    sender.send(UpdateMsg::CheckUpdate)?;
    Ok(())
}

#[allow(dead_code)]
pub fn stop_auto_update() {
    let sender = TX_MSG.lock().unwrap();
    sender.send(UpdateMsg::Exit).unwrap_or_default();
}

#[cfg(target_os = "windows")]
pub fn install_support_update(download_url: String) -> ResultType<()> {
    if !crate::platform::is_installed() || !crate::platform::windows::is_root() {
        bail!("Aktualizacja wymaga uruchomionej usługi systemowej.");
    }
    if !has_no_active_conns() {
        bail!("Zakończ aktywne sesje przed aktualizacją.");
    }

    let (installer, update_channel) = download_managed_msi(download_url)?;
    if !has_no_active_conns() {
        std::fs::remove_file(&installer).ok();
        bail!("Zakończ aktywne sesje przed aktualizacją.");
    }

    let mut child = match spawn_managed_msi(&installer, true) {
        Ok(child) => child,
        Err(error) => {
            std::fs::remove_file(&installer).ok();
            return Err(error);
        }
    };
    let pid = child.id();
    log::info!(
        "Managed update installer started, pid: {}, channel: {}, file: {:?}",
        pid,
        update_channel,
        installer
    );
    std::thread::spawn(move || {
        let _ = child.wait();
        std::fs::remove_file(installer).ok();
    });
    Ok(())
}

#[cfg(all(target_os = "windows", feature = "flutter"))]
pub fn install_quick_support_as_helpdesk(download_url: String) -> ResultType<()> {
    if option_env!("CLIENT_VARIANT").unwrap_or("").trim() != "quick_support" {
        bail!("Ten build nie jest aplikacją Quick Support.");
    }
    if crate::platform::is_installed() {
        bail!("Aplikacja jest już zainstalowana.");
    }

    let (installer, update_channel) = download_managed_msi(download_url)?;
    if update_channel != "windows_helpdesk" {
        std::fs::remove_file(&installer).ok();
        bail!("Quick Support może zainstalować wyłącznie profil Windows Helpdesk.");
    }
    let mut child = match spawn_managed_msi(&installer, false) {
        Ok(child) => child,
        Err(error) => {
            std::fs::remove_file(&installer).ok();
            return Err(error);
        }
    };
    let pid = child.id();
    log::info!(
        "Quick Support started Windows Helpdesk installer, pid: {}, file: {:?}",
        pid,
        installer
    );
    let status = child.wait();
    std::fs::remove_file(installer).ok();
    let status = status?;
    if !status.success() && status.code() != Some(3010) {
        bail!(
            "Instalacja Windows Helpdesk zakończyła się kodem {}.",
            status.code().unwrap_or(-1)
        );
    }
    Ok(())
}

#[cfg(target_os = "windows")]
fn download_managed_msi(download_url: String) -> ResultType<(PathBuf, String)> {
    let configured_base = option_env!("RDBK_API_URL").unwrap_or("").trim();
    if configured_base.is_empty() {
        bail!("W tym buildzie nie skonfigurowano serwera aktualizacji.");
    }
    let update_channel = option_env!("RDBK_UPDATE_CHANNEL").unwrap_or("").trim();
    if !matches!(update_channel, "windows_support" | "windows_helpdesk") {
        bail!("W tym buildzie nie skonfigurowano kanału aktualizacji.");
    }
    let base = url::Url::parse(configured_base)?;
    let candidate = url::Url::parse(&download_url)?;
    let expected_path = format!("/downloads/client-update/{update_channel}/");
    let same_origin = candidate.scheme() == base.scheme()
        && candidate.host_str() == base.host_str()
        && candidate.port_or_known_default() == base.port_or_known_default();
    if !same_origin
        || candidate.username() != ""
        || candidate.password().is_some()
        || candidate.fragment().is_some()
        || candidate.query().is_some()
        || !candidate.path().starts_with(&expected_path)
    {
        bail!("Serwer odrzucił nieprawidłowy adres aktualizacji.");
    }

    let client = reqwest::blocking::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .connect_timeout(Duration::from_secs(10))
        .timeout(Duration::from_secs(300))
        .build()?;
    let mut response = client.get(candidate).send()?;
    if !response.status().is_success() {
        bail!(
            "Pobranie aktualizacji nie powiodło się: {}",
            response.status()
        );
    }
    if let Some(length) = response.content_length() {
        if length == 0 || length > SUPPORT_UPDATE_MAX_BYTES {
            bail!("Instalator ma nieprawidłowy rozmiar.");
        }
    }

    let unique = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_nanos();
    let installer = std::env::temp_dir().join(format!(
        "proste-it-client-update-{}-{unique}.msi",
        std::process::id()
    ));
    let mut output = std::fs::OpenOptions::new()
        .create_new(true)
        .write(true)
        .open(&installer)?;
    let mut limited = response.by_ref().take(SUPPORT_UPDATE_MAX_BYTES + 1);
    let written = std::io::copy(&mut limited, &mut output)?;
    output.sync_all()?;
    if written == 0 || written > SUPPORT_UPDATE_MAX_BYTES {
        std::fs::remove_file(&installer).ok();
        bail!("Instalator ma nieprawidłowy rozmiar.");
    }
    drop(output);

    let mut signature = [0_u8; 8];
    std::fs::File::open(&installer)?.read_exact(&mut signature)?;
    if signature != [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1] {
        std::fs::remove_file(&installer).ok();
        bail!("Pobrany plik nie jest instalatorem MSI.");
    }
    if let Err(error) = verify_managed_msi_signature(&installer) {
        std::fs::remove_file(&installer).ok();
        return Err(error);
    }
    Ok((installer, update_channel.to_owned()))
}

#[cfg(target_os = "windows")]
fn verify_managed_msi_signature(installer: &std::path::Path) -> ResultType<()> {
    let system_root = std::env::var_os("SystemRoot")
        .ok_or_else(|| hbb_common::anyhow::anyhow!("Brak katalogu systemowego Windows."))?;
    let powershell = PathBuf::from(system_root)
        .join("System32")
        .join("WindowsPowerShell")
        .join("v1.0")
        .join("powershell.exe");
    let expected_subject = option_env!("RDBK_WINDOWS_SIGNER_SUBJECT")
        .unwrap_or("")
        .trim();
    let status = std::process::Command::new(powershell)
        .env("RDBK_MSI_PATH", installer)
        .env("RDBK_SIGNER_SUBJECT", expected_subject)
        .args([
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            "$s=Get-AuthenticodeSignature -LiteralPath $env:RDBK_MSI_PATH;if($s.Status -ne 'Valid'){exit 2};if($env:RDBK_SIGNER_SUBJECT -and $s.SignerCertificate.Subject -notlike ('*'+$env:RDBK_SIGNER_SUBJECT+'*')){exit 3}",
        ])
        .status()?;
    if !status.success() {
        bail!("Podpis cyfrowy instalatora jest nieprawidłowy lub pochodzi od innego wydawcy.");
    }
    Ok(())
}

#[cfg(target_os = "windows")]
fn spawn_managed_msi(installer: &std::path::Path, silent: bool) -> ResultType<std::process::Child> {
    let system_root = std::env::var_os("SystemRoot")
        .ok_or_else(|| hbb_common::anyhow::anyhow!("Brak katalogu systemowego Windows."))?;
    let msiexec = PathBuf::from(system_root)
        .join("System32")
        .join("msiexec.exe");
    let installer = installer
        .to_str()
        .ok_or_else(|| hbb_common::anyhow::anyhow!("Nieprawidłowa ścieżka instalatora."))?;
    let mut command = std::process::Command::new(msiexec);
    command.args(["/i", installer]);
    if silent {
        command.args(["/qn", "LAUNCH_TRAY_APP=N"]);
    } else {
        command.args(["/passive", "LAUNCH_TRAY_APP=Y"]);
    }
    command.args(["REBOOT=ReallySuppress", "/norestart"]);
    Ok(command.spawn()?)
}

#[inline]
fn has_no_active_conns() -> bool {
    let conns = crate::Connection::alive_conns();
    conns.is_empty() && has_no_controlling_conns()
}

#[cfg(any(not(target_os = "windows"), feature = "flutter"))]
fn has_no_controlling_conns() -> bool {
    CONTROLLING_SESSION_COUNT.load(Ordering::SeqCst) == 0
}

#[cfg(not(any(not(target_os = "windows"), feature = "flutter")))]
fn has_no_controlling_conns() -> bool {
    let app_exe = format!("{}.exe", crate::get_app_name().to_lowercase());
    for arg in [
        "--connect",
        "--play",
        "--file-transfer",
        "--view-camera",
        "--port-forward",
        "--rdp",
    ] {
        if !crate::platform::get_pids_of_process_with_first_arg(&app_exe, arg).is_empty() {
            return false;
        }
    }
    true
}

fn start_auto_update_check() -> Sender<UpdateMsg> {
    let (tx, rx) = channel();
    std::thread::spawn(move || start_auto_update_check_(rx));
    return tx;
}

fn start_auto_update_check_(rx_msg: Receiver<UpdateMsg>) {
    std::thread::sleep(Duration::from_secs(30));
    if let Err(e) = check_update(false) {
        log::error!("Error checking for updates: {}", e);
    }

    const MIN_INTERVAL: Duration = Duration::from_secs(60 * 10);
    const RETRY_INTERVAL: Duration = Duration::from_secs(60 * 30);
    let mut last_check_time = Instant::now();
    let mut check_interval = DUR_ONE_DAY;
    loop {
        let recv_res = rx_msg.recv_timeout(check_interval);
        match &recv_res {
            Ok(UpdateMsg::CheckUpdate) | Err(_) => {
                if last_check_time.elapsed() < MIN_INTERVAL {
                    // log::debug!("Update check skipped due to minimum interval.");
                    continue;
                }
                // Don't check update if there are alive connections.
                if !has_no_active_conns() {
                    check_interval = RETRY_INTERVAL;
                    continue;
                }
                if let Err(e) = check_update(matches!(recv_res, Ok(UpdateMsg::CheckUpdate))) {
                    log::error!("Error checking for updates: {}", e);
                    check_interval = RETRY_INTERVAL;
                } else {
                    last_check_time = Instant::now();
                    check_interval = DUR_ONE_DAY;
                }
            }
            Ok(UpdateMsg::Exit) => break,
        }
    }
}

fn check_update(manually: bool) -> ResultType<()> {
    #[cfg(target_os = "windows")]
    let update_msi = crate::platform::is_msi_installed()? && !crate::is_custom_client();
    if !(manually || config::Config::get_bool_option(config::keys::OPTION_ALLOW_AUTO_UPDATE)) {
        return Ok(());
    }
    if do_check_software_update().is_err() {
        // ignore
        return Ok(());
    }

    let update_url = crate::common::SOFTWARE_UPDATE_URL.lock().unwrap().clone();
    if update_url.is_empty() {
        log::debug!("No update available.");
    } else {
        let download_url = update_url.replace("tag", "download");
        let version = download_url.split('/').last().unwrap_or_default();
        #[cfg(target_os = "windows")]
        let download_url = if cfg!(feature = "flutter") {
            let Some(arch) = crate::platform::windows::release_arch_suffix() else {
                bail!(
                    "Unsupported Windows release architecture: {}",
                    std::env::consts::ARCH
                );
            };
            format!(
                "{}/rustdesk-{}-{}.{}",
                download_url,
                version,
                arch,
                if update_msi { "msi" } else { "exe" }
            )
        } else {
            format!("{}/rustdesk-{}-x86-sciter.exe", download_url, version)
        };
        log::debug!("New version available: {}", &version);
        let client = create_http_client_with_url(&download_url);
        let Some(file_path) = get_download_file_from_url(&download_url) else {
            bail!("Failed to get the file path from the URL: {}", download_url);
        };
        let mut is_file_exists = false;
        if file_path.exists() {
            // Check if the file size is the same as the server file size
            // If the file size is the same, we don't need to download it again.
            let file_size = std::fs::metadata(&file_path)?.len();
            let response = client.head(&download_url).send()?;
            if !response.status().is_success() {
                bail!("Failed to get the file size: {}", response.status());
            }
            let total_size = response
                .headers()
                .get(reqwest::header::CONTENT_LENGTH)
                .and_then(|ct_len| ct_len.to_str().ok())
                .and_then(|ct_len| ct_len.parse::<u64>().ok());
            let Some(total_size) = total_size else {
                bail!("Failed to get content length");
            };
            if file_size == total_size {
                is_file_exists = true;
            } else {
                std::fs::remove_file(&file_path)?;
            }
        }
        if !is_file_exists {
            let response = client.get(&download_url).send()?;
            if !response.status().is_success() {
                bail!(
                    "Failed to download the new version file: {}",
                    response.status()
                );
            }
            let file_data = response.bytes()?;
            let mut file = std::fs::File::create(&file_path)?;
            file.write_all(&file_data)?;
        }
        // We have checked if the `conns` is empty before, but we need to check again.
        // No need to care about the downloaded file here, because it's rare case that the `conns` are empty
        // before the download, but not empty after the download.
        if has_no_active_conns() {
            #[cfg(target_os = "windows")]
            update_new_version(update_msi, &version, &file_path);
        }
    }
    Ok(())
}

#[cfg(target_os = "windows")]
fn update_new_version(update_msi: bool, version: &str, file_path: &PathBuf) {
    log::debug!(
        "New version is downloaded, update begin, update msi: {update_msi}, version: {version}, file: {:?}",
        file_path.to_str()
    );
    if let Some(p) = file_path.to_str() {
        if let Some(session_id) = crate::platform::get_current_process_session_id() {
            if update_msi {
                match crate::platform::update_me_msi(p, true) {
                    Ok(_) => {
                        log::debug!("New version \"{}\" updated.", version);
                    }
                    Err(e) => {
                        log::error!(
                            "Failed to install the new msi version  \"{}\": {}",
                            version,
                            e
                        );
                        std::fs::remove_file(&file_path).ok();
                    }
                }
            } else {
                let custom_client_staging_dir = if crate::is_custom_client() {
                    let custom_client_staging_dir =
                        crate::platform::get_custom_client_staging_dir();
                    if let Err(e) = crate::platform::handle_custom_client_staging_dir_before_update(
                        &custom_client_staging_dir,
                    ) {
                        log::error!(
                            "Failed to handle custom client staging dir before update: {}",
                            e
                        );
                        std::fs::remove_file(&file_path).ok();
                        return;
                    }
                    Some(custom_client_staging_dir)
                } else {
                    // Clean up any residual staging directory from previous custom client
                    let staging_dir = crate::platform::get_custom_client_staging_dir();
                    hbb_common::allow_err!(crate::platform::remove_custom_client_staging_dir(
                        &staging_dir
                    ));
                    None
                };
                let update_launched = match crate::platform::launch_privileged_process(
                    session_id,
                    &format!("{} --update", p),
                ) {
                    Ok(h) => {
                        if h.is_null() {
                            log::error!("Failed to update to the new version: {}", version);
                            false
                        } else {
                            log::debug!("New version \"{}\" is launched.", version);
                            true
                        }
                    }
                    Err(e) => {
                        log::error!("Failed to run the new version: {}", e);
                        false
                    }
                };
                if !update_launched {
                    if let Some(dir) = custom_client_staging_dir {
                        hbb_common::allow_err!(crate::platform::remove_custom_client_staging_dir(
                            &dir
                        ));
                    }
                    std::fs::remove_file(&file_path).ok();
                }
            }
        } else {
            log::error!(
                "Failed to get the current process session id, Error {}",
                std::io::Error::last_os_error()
            );
            std::fs::remove_file(&file_path).ok();
        }
    } else {
        // unreachable!()
        log::error!(
            "Failed to convert the file path to string: {}",
            file_path.display()
        );
    }
}

pub fn get_download_file_from_url(url: &str) -> Option<PathBuf> {
    let filename = url.split('/').last()?;
    Some(std::env::temp_dir().join(filename))
}
