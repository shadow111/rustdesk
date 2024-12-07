use std::{
    collections::HashMap,
    iter::FromIterator,
    sync::{Arc, Mutex},
};

use sciter::Value;

use hbb_common::{
    allow_err,
    config::{LocalConfig, PeerConfig},
    log,
};

#[cfg(not(any(feature = "flutter", feature = "cli")))]
use crate::ui_session_interface::Session;
use crate::{common::get_app_name, ipc, ui_interface::*};

mod cm;
#[cfg(feature = "inline")]
pub mod inline;
pub mod remote;

#[allow(dead_code)]
type Status = (i32, bool, i64, String);

lazy_static::lazy_static! {
    // stupid workaround for https://sciter.com/forums/topic/crash-on-latest-tis-mac-sdk-sometimes/
    static ref STUPID_VALUES: Mutex<Vec<Arc<Vec<Value>>>> = Default::default();
}

#[cfg(not(any(feature = "flutter", feature = "cli")))]
lazy_static::lazy_static! {
    pub static ref CUR_SESSION: Arc<Mutex<Option<Session<remote::SciterHandler>>>> = Default::default();
}

struct UIHostHandler;

pub fn start(args: &mut [String]) {
    #[cfg(target_os = "macos")]
    crate::platform::delegate::show_dock();
    #[cfg(all(target_os = "linux", feature = "inline"))]
    {
        let app_dir = std::env::var("APPDIR").unwrap_or("".to_string());
        let mut so_path = "/usr/lib/rustdesk/libsciter-gtk.so".to_owned();
        for (prefix, dir) in [
            ("", "/usr"),
            ("", "/app"),
            (&app_dir, "/usr"),
            (&app_dir, "/app"),
        ]
        .iter()
        {
            let path = format!("{prefix}{dir}/lib/rustdesk/libsciter-gtk.so");
            if std::path::Path::new(&path).exists() {
                so_path = path;
                break;
            }
        }
        sciter::set_library(&so_path).ok();
    }
    #[cfg(windows)]
    // Check if there is a sciter.dll nearby.
    if let Ok(exe) = std::env::current_exe() {
        if let Some(parent) = exe.parent() {
            let sciter_dll_path = parent.join("sciter.dll");
            if sciter_dll_path.exists() {
                // Try to set the sciter dll.
                let p = sciter_dll_path.to_string_lossy().to_string();
                log::debug!("Found dll:{}, \n {:?}", p, sciter::set_library(&p));
            }
        }
    }
    // https://github.com/c-smile/sciter-sdk/blob/master/include/sciter-x-types.h
    // https://github.com/rustdesk/rustdesk/issues/132#issuecomment-886069737
    #[cfg(windows)]
    allow_err!(sciter::set_options(sciter::RuntimeOptions::GfxLayer(
        sciter::GFX_LAYER::WARP
    )));
    use sciter::SCRIPT_RUNTIME_FEATURES::*;
    allow_err!(sciter::set_options(sciter::RuntimeOptions::ScriptFeatures(
        ALLOW_FILE_IO as u8 | ALLOW_SOCKET_IO as u8 | ALLOW_EVAL as u8 | ALLOW_SYSINFO as u8
    )));
    let mut frame = sciter::WindowBuilder::main_window().create();
    #[cfg(windows)]
    allow_err!(sciter::set_options(sciter::RuntimeOptions::UxTheming(true)));
    frame.set_title(&crate::get_app_name());
    #[cfg(target_os = "macos")]
    crate::platform::delegate::make_menubar(frame.get_host(), args.is_empty());
    #[cfg(windows)]
    crate::platform::try_set_window_foreground(frame.get_hwnd() as _);
    let page;
    if args.len() > 1 && args[0] == "--play" {
        args[0] = "--connect".to_owned();
        let path: std::path::PathBuf = (&args[1]).into();
        let id = path
            .file_stem()
            .map(|p| p.to_str().unwrap_or(""))
            .unwrap_or("")
            .to_owned();
        args[1] = id;
    }
    if args.is_empty() {
        std::thread::spawn(move || check_zombie());
        crate::common::check_software_update();
        frame.event_handler(UI {});
        frame.sciter_handler(UIHostHandler {});
        page = "index.html";
        // Start pulse audio local server.
        #[cfg(target_os = "linux")]
        std::thread::spawn(crate::ipc::start_pa);
    } else if args[0] == "--install" {
        frame.event_handler(UI {});
        frame.sciter_handler(UIHostHandler {});
        page = "install.html";
    } else if args[0] == "--cm" {
        frame.register_behavior("connection-manager", move || {
            Box::new(cm::SciterConnectionManager::new())
        });
        page = "cm.html";
    } else if (args[0] == "--connect"
        || args[0] == "--file-transfer"
        || args[0] == "--port-forward"
        || args[0] == "--rdp")
        && args.len() > 1
    {
        #[cfg(windows)]
        {
            let hw = frame.get_host().get_hwnd();
            crate::platform::windows::enable_lowlevel_keyboard(hw as _);
        }
        let mut iter = args.iter();
        let Some(cmd) = iter.next() else {
            log::error!("Failed to get cmd arg");
            return;
        };
        let cmd = cmd.to_owned();
        let Some(id) = iter.next() else {
            log::error!("Failed to get id arg");
            return;
        };
        let id = id.to_owned();
        let pass = iter.next().unwrap_or(&"".to_owned()).clone();
        let args: Vec<String> = iter.map(|x| x.clone()).collect();
        frame.set_title(&id);
        frame.register_behavior("native-remote", move || {
            let handler =
                remote::SciterSession::new(cmd.clone(), id.clone(), pass.clone(), args.clone());
            #[cfg(not(any(feature = "flutter", feature = "cli")))]
            {
                *CUR_SESSION.lock().unwrap() = Some(handler.inner());
            }
            Box::new(handler)
        });
        page = "remote.html";
    } else {
        log::error!("Wrong command: {:?}", args);
        return;
    }
    #[cfg(feature = "inline")]
    {
        let html = if page == "index.html" {
            inline::get_index()
        } else if page == "cm.html" {
            inline::get_cm()
        } else if page == "install.html" {
            inline::get_install()
        } else {
            inline::get_remote()
        };
        frame.load_html(html.as_bytes(), Some(page));
    }
    #[cfg(not(feature = "inline"))]
    frame.load_file(&format!(
        "file://{}/src/ui/{}",
        std::env::current_dir()
            .map(|c| c.display().to_string())
            .unwrap_or("".to_owned()),
        page
    ));
    frame.run_app();
}

struct UI {}

impl UI {
    fn recent_sessions_updated(&self) -> bool {
        recent_sessions_updated()
    }

    fn get_id(&self) -> String {
        ipc::get_id()
    }

    fn temporary_password(&mut self) -> String {
        temporary_password()
    }

    fn update_temporary_password(&self) {
        update_temporary_password()
    }

    fn permanent_password(&self) -> String {
        permanent_password()
    }

    fn set_permanent_password(&self, password: String) {
        set_permanent_password(password);
    }

    fn get_remote_id(&mut self) -> String {
        LocalConfig::get_remote_id()
    }

    fn set_remote_id(&mut self, id: String) {
        LocalConfig::set_remote_id(&id);
    }

    fn goto_install(&mut self) {
        goto_install();
    }

    fn install_me(&mut self, _options: String, _path: String) {
        install_me(_options, _path, false, false);
    }

    fn update_me(&self, _path: String) {
        update_me(_path);
    }

    fn run_without_install(&self) {
        run_without_install();
    }

    fn show_run_without_install(&self) -> bool {
        show_run_without_install()
    }

    fn get_license(&self) -> String {
        get_license()
    }

    fn get_option(&self, key: String) -> String {
        get_option(key)
    }

    fn get_local_option(&self, key: String) -> String {
        get_local_option(key)
    }

    fn set_local_option(&self, key: String, value: String) {
        set_local_option(key, value);
    }

    fn peer_has_password(&self, id: String) -> bool {
        peer_has_password(id)
    }

    fn forget_password(&self, id: String) {
        forget_password(id)
    }

    fn get_peer_option(&self, id: String, name: String) -> String {
        get_peer_option(id, name)
    }

    fn set_peer_option(&self, id: String, name: String, value: String) {
        set_peer_option(id, name, value)
    }

    fn using_public_server(&self) -> bool {
        crate::using_public_server()
    }

    fn get_options(&self) -> Value {
        let hashmap: HashMap<String, String> =
            serde_json::from_str(&get_options()).unwrap_or_default();
        let mut m = Value::map();
        for (k, v) in hashmap {
            m.set_item(k, v);
        }
        m
    }

    fn test_if_valid_server(&self, host: String, test_with_proxy: bool) -> String {
        test_if_valid_server(host, test_with_proxy)
    }

    fn get_sound_inputs(&self) -> Value {
        Value::from_iter(get_sound_inputs())
    }

    fn set_options(&self, v: Value) {
        let mut m = HashMap::new();
        for (k, v) in v.items() {
            if let Some(k) = k.as_string() {
                if let Some(v) = v.as_string() {
                    if !v.is_empty() {
                        m.insert(k, v);
                    }
                }
            }
        }
        set_options(m);
    }

    fn set_option(&self, key: String, value: String) {
        set_option(key, value);
    }

    fn install_path(&mut self) -> String {
        install_path()
    }

    fn install_options(&self) -> String {
        install_options()
    }

    fn get_socks(&self) -> Value {
        Value::from_iter(get_socks())
    }

    fn set_socks(&self, proxy: String, username: String, password: String) {
        set_socks(proxy, username, password)
    }

    fn is_installed(&self) -> bool {
        is_installed()
    }

    fn is_root(&self) -> bool {
        is_root()
    }

    fn is_release(&self) -> bool {
        #[cfg(not(debug_assertions))]
        return true;
        #[cfg(debug_assertions)]
        return false;
    }

    fn is_share_rdp(&self) -> bool {
        is_share_rdp()
    }

    fn set_share_rdp(&self, _enable: bool) {
        set_share_rdp(_enable);
    }

    fn is_installed_lower_version(&self) -> bool {
        is_installed_lower_version()
    }

    fn closing(&mut self, x: i32, y: i32, w: i32, h: i32) {
        crate::server::input_service::fix_key_down_timeout_at_exit();
        LocalConfig::set_size(x, y, w, h);
    }

    fn get_size(&mut self) -> Value {
        let s = LocalConfig::get_size();
        let mut v = Vec::new();
        v.push(s.0);
        v.push(s.1);
        v.push(s.2);
        v.push(s.3);
        Value::from_iter(v)
    }

    fn get_mouse_time(&self) -> f64 {
        get_mouse_time()
    }

    fn check_mouse_time(&self) {
        check_mouse_time()
    }

    fn get_connect_status(&mut self) -> Value {
        let mut v = Value::array(0);
        let x = get_connect_status();
        v.push(x.status_num);
        v.push(x.key_confirmed);
        v.push(x.id);
        v
    }

    #[inline]
    fn get_peer_value(id: String, p: PeerConfig) -> Value {
        let values = vec![
            id,
            p.info.username.clone(),
            p.info.hostname.clone(),
            p.info.platform.clone(),
            p.options.get("alias").unwrap_or(&"".to_owned()).to_owned(),
        ];
        Value::from_iter(values)
    }

    fn get_peer(&self, id: String) -> Value {
        let c = get_peer(id.clone());
        Self::get_peer_value(id, c)
    }

    fn get_fav(&self) -> Value {
        Value::from_iter(get_fav())
    }

    fn store_fav(&self, fav: Value) {
        let mut tmp = vec![];
        fav.values().for_each(|v| {
            if let Some(v) = v.as_string() {
                if !v.is_empty() {
                    tmp.push(v);
                }
            }
        });
        store_fav(tmp);
    }

    fn get_recent_sessions(&mut self) -> Value {
        // to-do: limit number of recent sessions, and remove old peer file
        let peers: Vec<Value> = PeerConfig::peers(None)
            .drain(..)
            .map(|p| Self::get_peer_value(p.0, p.2))
            .collect();
        Value::from_iter(peers)
    }

    fn get_icon(&mut self) -> String {
        get_icon()
    }

    fn remove_peer(&mut self, id: String) {
        PeerConfig::remove(&id);
    }

    fn remove_discovered(&mut self, id: String) {
        remove_discovered(id);
    }

    fn send_wol(&mut self, id: String) {
        crate::lan::send_wol(id)
    }

    fn new_remote(&mut self, id: String, remote_type: String, force_relay: bool) {
        new_remote(id, remote_type, force_relay)
    }

    fn is_process_trusted(&mut self, _prompt: bool) -> bool {
        is_process_trusted(_prompt)
    }

    fn is_can_screen_recording(&mut self, _prompt: bool) -> bool {
        is_can_screen_recording(_prompt)
    }

    fn is_installed_daemon(&mut self, _prompt: bool) -> bool {
        is_installed_daemon(_prompt)
    }

    fn get_error(&mut self) -> String {
        get_error()
    }

    fn is_login_wayland(&mut self) -> bool {
        is_login_wayland()
    }

    fn current_is_wayland(&mut self) -> bool {
        current_is_wayland()
    }

    fn get_software_update_url(&self) -> String {
        crate::SOFTWARE_UPDATE_URL.lock().unwrap().clone()
    }

    fn get_new_version(&self) -> String {
        get_new_version()
    }

    fn get_version(&self) -> String {
        get_version()
    }

    fn get_fingerprint(&self) -> String {
        get_fingerprint()
    }

    fn get_app_name(&self) -> String {
        get_app_name()
    }

    fn get_software_ext(&self) -> String {
        #[cfg(windows)]
        let p = "exe";
        #[cfg(target_os = "macos")]
        let p = "dmg";
        #[cfg(target_os = "linux")]
        let p = "deb";
        p.to_owned()
    }

    fn get_software_store_path(&self) -> String {
        let mut p = std::env::temp_dir();
        let name = crate::SOFTWARE_UPDATE_URL
            .lock()
            .unwrap()
            .split("/")
            .last()
            .map(|x| x.to_owned())
            .unwrap_or(crate::get_app_name());
        p.push(name);
        format!("{}.{}", p.to_string_lossy(), self.get_software_ext())
    }

    fn create_shortcut(&self, _id: String) {
        #[cfg(windows)]
        create_shortcut(_id)
    }

    fn discover(&self) {
        std::thread::spawn(move || {
            allow_err!(crate::lan::discover());
        });
    }

    fn get_lan_peers(&self) -> String {
        // let peers = get_lan_peers()
        //     .into_iter()
        //     .map(|mut peer| {
        //         (
        //             peer.remove("id").unwrap_or_default(),
        //             peer.remove("username").unwrap_or_default(),
        //             peer.remove("hostname").unwrap_or_default(),
        //             peer.remove("platform").unwrap_or_default(),
        //         )
        //     })
        //     .collect::<Vec<(String, String, String, String)>>();
        serde_json::to_string(&get_lan_peers()).unwrap_or_default()
    }

    fn get_uuid(&self) -> String {
        get_uuid()
    }

    fn open_url(&self, url: String) {
        #[cfg(windows)]
        let p = "explorer";
        #[cfg(target_os = "macos")]
        let p = "open";
        #[cfg(target_os = "linux")]
        let p = if std::path::Path::new("/usr/bin/firefox").exists() {
            "firefox"
        } else {
            "xdg-open"
        };
        allow_err!(std::process::Command::new(p).arg(url).spawn());
    }

    fn change_id(&self, id: String) {
        reset_async_job_status();
        let old_id = self.get_id();
        change_id_shared(id, old_id);
    }

    fn http_request(&self, url: String, method: String, body: Option<String>, header: String) {
        http_request(url, method, body, header)
    }

    fn post_request(&self, url: String, body: String, header: String) {
        post_request(url, body, header)
    }

    fn is_ok_change_id(&self) -> bool {
        hbb_common::machine_uid::get().is_ok()
    }

    fn get_async_job_status(&self) -> String {
        get_async_job_status()
    }

    fn get_http_status(&self, url: String) -> Option<String> {
        get_async_http_status(url)
    }

    fn t(&self, name: String) -> String {
        crate::client::translate(name)
    }

    fn is_xfce(&self) -> bool {
        crate::platform::is_xfce()
    }

    fn get_api_server(&self) -> String {
        get_api_server()
    }

    fn has_hwcodec(&self) -> bool {
        has_hwcodec()
    }

    fn has_vram(&self) -> bool {
        has_vram()
    }

    fn get_langs(&self) -> String {
        get_langs()
    }

    fn video_save_directory(&self, root: bool) -> String {
        video_save_directory(root)
    }

    fn handle_relay_id(&self, id: String) -> String {
        handle_relay_id(&id).to_owned()
    }

    fn get_login_device_info(&self) -> String {
        get_login_device_info_json()
    }

    fn support_remove_wallpaper(&self) -> bool {
        support_remove_wallpaper()
    }

    fn has_valid_2fa(&self) -> bool {
        has_valid_2fa()
    }

    fn generate2fa(&self) -> String {
        generate2fa()
    }

    pub fn verify2fa(&self, code: String) -> bool {
        verify2fa(code)
    }

    fn generate_2fa_img_src(&self, data: String) -> String {
        let v = qrcode_generator::to_png_to_vec(data, qrcode_generator::QrCodeEcc::Low, 128)
            .unwrap_or_default();
        let s = hbb_common::sodiumoxide::base64::encode(
            v,
            hbb_common::sodiumoxide::base64::Variant::Original,
        );
        format!("data:image/png;base64,{s}")
    }

    pub fn check_hwcodec(&self) {
        check_hwcodec()
    }
}

impl sciter::EventHandler for UI {
    sciter::dispatch_script_call! {
        fn t(String);
        fn get_api_server();
        fn is_xfce();
        fn using_public_server();
        fn get_id();
        fn temporary_password();
        fn update_temporary_password();
        fn permanent_password();
        fn set_permanent_password(String);
        fn get_remote_id();
        fn set_remote_id(String);
        fn closing(i32, i32, i32, i32);
        fn get_size();
        fn new_remote(String, String, bool);
        fn send_wol(String);
        fn remove_peer(String);
        fn remove_discovered(String);
        fn get_connect_status();
        fn get_mouse_time();
        fn check_mouse_time();
        fn get_recent_sessions();
        fn get_peer(String);
        fn get_fav();
        fn store_fav(Value);
        fn recent_sessions_updated();
        fn get_icon();
        fn install_me(String, String);
        fn is_installed();
        fn is_root();
        fn is_release();
        fn set_socks(String, String, String);
        fn get_socks();
        fn is_share_rdp();
        fn set_share_rdp(bool);
        fn is_installed_lower_version();
        fn install_path();
        fn install_options();
        fn goto_install();
        fn is_process_trusted(bool);
        fn is_can_screen_recording(bool);
        fn is_installed_daemon(bool);
        fn get_error();
        fn is_login_wayland();
        fn current_is_wayland();
        fn get_options();
        fn get_option(String);
        fn get_local_option(String);
        fn set_local_option(String, String);
        fn get_peer_option(String, String);
        fn peer_has_password(String);
        fn forget_password(String);
        fn set_peer_option(String, String, String);
        fn get_license();
        fn test_if_valid_server(String, bool);
        fn get_sound_inputs();
        fn set_options(Value);
        fn set_option(String, String);
        fn get_software_update_url();
        fn get_new_version();
        fn get_version();
        fn get_fingerprint();
        fn update_me(String);
        fn show_run_without_install();
        fn run_without_install();
        fn get_app_name();
        fn get_software_store_path();
        fn get_software_ext();
        fn open_url(String);
        fn change_id(String);
        fn get_async_job_status();
        fn post_request(String, String, String);
        fn is_ok_change_id();
        fn create_shortcut(String);
        fn discover();
        fn get_lan_peers();
        fn get_uuid();
        fn has_hwcodec();
        fn has_vram();
        fn get_langs();
        fn video_save_directory(bool);
        fn handle_relay_id(String);
        fn get_login_device_info();
        fn support_remove_wallpaper();
        fn has_valid_2fa();
        fn generate2fa();
        fn generate_2fa_img_src(String);
        fn verify2fa(String);
        fn check_hwcodec();
    }
}

impl sciter::host::HostHandler for UIHostHandler {
    fn on_graphics_critical_failure(&mut self) {
        log::error!("Critical rendering error: e.g. DirectX gfx driver error. Most probably bad gfx drivers.");
    }
}

#[cfg(not(target_os = "linux"))]
fn get_sound_inputs() -> Vec<String> {
    let mut out = Vec::new();
    use cpal::traits::{DeviceTrait, HostTrait};
    let host = cpal::default_host();
    if let Ok(devices) = host.devices() {
        for device in devices {
            if device.default_input_config().is_err() {
                continue;
            }
            if let Ok(name) = device.name() {
                out.push(name);
            }
        }
    }
    out
}

#[cfg(target_os = "linux")]
fn get_sound_inputs() -> Vec<String> {
    crate::platform::linux::get_pa_sources()
        .drain(..)
        .map(|x| x.1)
        .collect()
}

// sacrifice some memory
pub fn value_crash_workaround(values: &[Value]) -> Arc<Vec<Value>> {
    let persist = Arc::new(values.to_vec());
    STUPID_VALUES.lock().unwrap().push(persist.clone());
    persist
}

pub fn get_icon() -> String {
    // 128x128
    #[cfg(target_os = "macos")]
    // 128x128 on 160x160 canvas, then shrink to 128, mac looks better with padding
    {
        "data:image/png;base64,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".into()
    }
    #[cfg(not(target_os = "macos"))] // 128x128 no padding
    {
        "data:image/png;base64,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".into()
    }
}
