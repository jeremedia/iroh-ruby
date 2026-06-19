//! Watcher callback bridges.
//!
//! `iroh::Endpoint` exposes a few values that change over time via the
//! `n0_watcher::Watcher` trait (`watch_addr`, `home_relay_status`, etc.). That
//! trait doesn't map naturally to uniffi, so the FFI exposes the same data via
//! callback traits: register a callback and get back a [`WatchHandle`] that
//! aborts the underlying task when dropped (or when [`WatchHandle::stop`] is
//! called).

use std::{
    future::Future,
    sync::{Arc, Condvar, Mutex as StdMutex},
    thread::JoinHandle,
    time::{Duration, Instant},
};

use iroh::Watcher;
use n0_future::{StreamExt, task::AbortOnDropHandle};
use tokio::sync::{Mutex, oneshot};

use crate::{CallbackError, EndpointAddr};

/// Callback invoked whenever the endpoint's [`EndpointAddr`] changes.
#[uniffi::export(with_foreign)]
#[async_trait::async_trait]
pub trait AddrChangeCallback: Send + Sync + 'static {
    async fn on_change(&self, addr: Arc<EndpointAddr>) -> Result<(), CallbackError>;
}

/// Callback invoked whenever the home-relay connection status list changes.
#[uniffi::export(with_foreign)]
#[async_trait::async_trait]
pub trait HomeRelayCallback: Send + Sync + 'static {
    async fn on_change(&self, relay_urls: Vec<String>) -> Result<(), CallbackError>;
}

/// Callback invoked when a network-stack change is detected (interface up/down,
/// roaming, etc.).
#[uniffi::export(with_foreign)]
#[async_trait::async_trait]
pub trait NetworkChangeCallback: Send + Sync + 'static {
    async fn on_change(&self) -> Result<(), CallbackError>;
}

/// Handle to a running watcher task. Drop it (or call [`Self::stop`]) to
/// unregister the callback.
#[derive(uniffi::Object)]
pub struct WatchHandle {
    task: Mutex<Option<AbortOnDropHandle<()>>>,
    cancel: StdMutex<Option<oneshot::Sender<()>>>,
    thread: StdMutex<Option<JoinHandle<()>>>,
}

impl WatchHandle {
    pub(crate) fn new(task: AbortOnDropHandle<()>) -> Self {
        Self {
            task: Mutex::new(Some(task)),
            cancel: StdMutex::new(None),
            thread: StdMutex::new(None),
        }
    }

    pub(crate) fn new_thread(cancel: oneshot::Sender<()>, thread: JoinHandle<()>) -> Self {
        Self {
            task: Mutex::new(None),
            cancel: StdMutex::new(Some(cancel)),
            thread: StdMutex::new(Some(thread)),
        }
    }
}

#[uniffi::export]
impl WatchHandle {
    /// Stop the watcher, aborting the background task.
    #[uniffi::method(async_runtime = "tokio")]
    pub async fn stop(&self) {
        self.task.lock().await.take();
        if let Some(cancel) = self.cancel.lock().unwrap().take() {
            let _ = cancel.send(());
        }
        if let Some(thread) = self.thread.lock().unwrap().take() {
            let _ = thread.join();
        }
    }
}

impl Drop for WatchHandle {
    fn drop(&mut self) {
        if let Some(cancel) = self.cancel.lock().unwrap().take() {
            let _ = cancel.send(());
        }
    }
}

#[derive(Debug, Default)]
struct AddrChangeRecorderState {
    event_count: u64,
    latest_addr: Option<EndpointAddr>,
}

struct AddrChangeRecorderInner {
    state: StdMutex<AddrChangeRecorderState>,
    changed: Condvar,
}

/// Native address-change recorder for language-binding watcher demos.
///
/// Ruby currently receives Rust-owned callback handles from UniFFI, but UniFFI
/// 0.31 does not generate the Ruby foreign-callback runtime needed for
/// Ruby-owned watcher implementations. This recorder gives Ruby examples a real
/// `AddrChangeCallback` handle while keeping observed watcher state queryable.
#[derive(uniffi::Object)]
pub struct AddrChangeRecorder {
    inner: Arc<AddrChangeRecorderInner>,
}

#[uniffi::export]
impl AddrChangeRecorder {
    #[uniffi::constructor]
    pub fn new() -> Self {
        Self {
            inner: Arc::new(AddrChangeRecorderInner {
                state: StdMutex::new(AddrChangeRecorderState::default()),
                changed: Condvar::new(),
            }),
        }
    }

    pub fn callback(&self) -> Arc<dyn AddrChangeCallback> {
        Arc::new(AddrChangeRecorderCallback {
            inner: self.inner.clone(),
        })
    }

    pub fn event_count(&self) -> u64 {
        self.inner.state.lock().unwrap().event_count
    }

    pub fn latest_addr(&self) -> Option<Arc<EndpointAddr>> {
        self.inner
            .state
            .lock()
            .unwrap()
            .latest_addr
            .clone()
            .map(Arc::new)
    }

    pub fn wait_for_events(&self, min_count: u64, timeout_ms: u64) -> bool {
        wait_for_state(
            &self.inner.state,
            &self.inner.changed,
            timeout_ms,
            |state| state.event_count >= min_count,
        )
    }
}

#[derive(Clone)]
struct AddrChangeRecorderCallback {
    inner: Arc<AddrChangeRecorderInner>,
}

#[async_trait::async_trait]
impl AddrChangeCallback for AddrChangeRecorderCallback {
    async fn on_change(&self, addr: Arc<EndpointAddr>) -> Result<(), CallbackError> {
        let mut state = self.inner.state.lock().unwrap();
        state.event_count += 1;
        state.latest_addr = Some((*addr).clone());
        self.inner.changed.notify_all();
        Ok(())
    }
}

#[derive(Debug, Default)]
struct HomeRelayRecorderState {
    event_count: u64,
    latest_relay_urls: Vec<String>,
}

struct HomeRelayRecorderInner {
    state: StdMutex<HomeRelayRecorderState>,
    changed: Condvar,
}

/// Native home-relay recorder for language-binding watcher demos.
#[derive(uniffi::Object)]
pub struct HomeRelayRecorder {
    inner: Arc<HomeRelayRecorderInner>,
}

#[uniffi::export]
impl HomeRelayRecorder {
    #[uniffi::constructor]
    pub fn new() -> Self {
        Self {
            inner: Arc::new(HomeRelayRecorderInner {
                state: StdMutex::new(HomeRelayRecorderState::default()),
                changed: Condvar::new(),
            }),
        }
    }

    pub fn callback(&self) -> Arc<dyn HomeRelayCallback> {
        Arc::new(HomeRelayRecorderCallback {
            inner: self.inner.clone(),
        })
    }

    pub fn event_count(&self) -> u64 {
        self.inner.state.lock().unwrap().event_count
    }

    pub fn latest_relay_urls(&self) -> Vec<String> {
        self.inner.state.lock().unwrap().latest_relay_urls.clone()
    }

    pub fn wait_for_events(&self, min_count: u64, timeout_ms: u64) -> bool {
        wait_for_state(
            &self.inner.state,
            &self.inner.changed,
            timeout_ms,
            |state| state.event_count >= min_count,
        )
    }
}

#[derive(Clone)]
struct HomeRelayRecorderCallback {
    inner: Arc<HomeRelayRecorderInner>,
}

#[async_trait::async_trait]
impl HomeRelayCallback for HomeRelayRecorderCallback {
    async fn on_change(&self, relay_urls: Vec<String>) -> Result<(), CallbackError> {
        let mut state = self.inner.state.lock().unwrap();
        state.event_count += 1;
        state.latest_relay_urls = relay_urls;
        self.inner.changed.notify_all();
        Ok(())
    }
}

#[derive(Debug, Default)]
struct NetworkChangeRecorderState {
    event_count: u64,
}

struct NetworkChangeRecorderInner {
    state: StdMutex<NetworkChangeRecorderState>,
    changed: Condvar,
}

/// Native network-change recorder for language-binding watcher demos.
#[derive(uniffi::Object)]
pub struct NetworkChangeRecorder {
    inner: Arc<NetworkChangeRecorderInner>,
}

#[uniffi::export]
impl NetworkChangeRecorder {
    #[uniffi::constructor]
    pub fn new() -> Self {
        Self {
            inner: Arc::new(NetworkChangeRecorderInner {
                state: StdMutex::new(NetworkChangeRecorderState::default()),
                changed: Condvar::new(),
            }),
        }
    }

    pub fn callback(&self) -> Arc<dyn NetworkChangeCallback> {
        Arc::new(NetworkChangeRecorderCallback {
            inner: self.inner.clone(),
        })
    }

    pub fn event_count(&self) -> u64 {
        self.inner.state.lock().unwrap().event_count
    }

    pub fn wait_for_events(&self, min_count: u64, timeout_ms: u64) -> bool {
        wait_for_state(
            &self.inner.state,
            &self.inner.changed,
            timeout_ms,
            |state| state.event_count >= min_count,
        )
    }
}

#[derive(Clone)]
struct NetworkChangeRecorderCallback {
    inner: Arc<NetworkChangeRecorderInner>,
}

#[async_trait::async_trait]
impl NetworkChangeCallback for NetworkChangeRecorderCallback {
    async fn on_change(&self) -> Result<(), CallbackError> {
        let mut state = self.inner.state.lock().unwrap();
        state.event_count += 1;
        self.inner.changed.notify_all();
        Ok(())
    }
}

fn wait_for_state<T, F>(
    state: &StdMutex<T>,
    changed: &Condvar,
    timeout_ms: u64,
    mut predicate: F,
) -> bool
where
    F: FnMut(&T) -> bool,
{
    let timeout = Duration::from_millis(timeout_ms);
    let deadline = Instant::now() + timeout;
    let mut guard = state.lock().unwrap();

    loop {
        if predicate(&guard) {
            return true;
        }

        let now = Instant::now();
        if now >= deadline {
            return false;
        }

        let remaining = deadline.saturating_duration_since(now);
        let (next_guard, result) = changed.wait_timeout(guard, remaining).unwrap();
        guard = next_guard;

        if result.timed_out() && !predicate(&guard) {
            return false;
        }
    }
}

pub(crate) fn spawn_watch_addr(
    endpoint: iroh::Endpoint,
    cb: Arc<dyn AddrChangeCallback>,
) -> WatchHandle {
    spawn_runtime_watch("iroh-ruby-watch-addr", move |mut cancel| async move {
        let mut stream = endpoint.watch_addr().stream();
        loop {
            tokio::select! {
                _ = &mut cancel => break,
                item = stream.next() => {
                    let Some(addr) = item else { break };
                    let mapped: EndpointAddr = addr.into();
                    if let Err(err) = cb.on_change(Arc::new(mapped)).await {
                        tracing::warn!("addr change callback error: {err:?}");
                        break;
                    }
                }
            }
        }
    })
}

pub(crate) fn spawn_home_relay_watch(
    endpoint: iroh::Endpoint,
    cb: Arc<dyn HomeRelayCallback>,
) -> WatchHandle {
    spawn_runtime_watch("iroh-ruby-watch-home-relay", move |mut cancel| async move {
        let mut stream = endpoint.home_relay_status().stream();
        loop {
            tokio::select! {
                _ = &mut cancel => break,
                item = stream.next() => {
                    let Some(statuses) = item else { break };
                    let urls: Vec<String> = statuses.into_iter().map(|s| s.url().to_string()).collect();
                    if let Err(err) = cb.on_change(urls).await {
                        tracing::warn!("home relay callback error: {err:?}");
                        break;
                    }
                }
            }
        }
    })
}

pub(crate) fn spawn_network_change_watch(
    endpoint: iroh::Endpoint,
    cb: Arc<dyn NetworkChangeCallback>,
) -> WatchHandle {
    spawn_runtime_watch("iroh-ruby-watch-network", move |mut cancel| async move {
        loop {
            tokio::select! {
                _ = &mut cancel => break,
                _ = endpoint.network_change() => {
                    if let Err(err) = cb.on_change().await {
                        tracing::warn!("network change callback error: {err:?}");
                        break;
                    }
                    tokio::time::sleep(Duration::from_millis(50)).await;
                }
            }
        }
    })
}

pub(crate) fn spawn_runtime_watch<F, Fut>(name: &'static str, run: F) -> WatchHandle
where
    F: FnOnce(oneshot::Receiver<()>) -> Fut + Send + 'static,
    Fut: Future<Output = ()> + Send + 'static,
{
    let (cancel_tx, cancel_rx) = oneshot::channel();
    let thread = std::thread::Builder::new()
        .name(name.to_string())
        .spawn(move || {
            let runtime = match tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
            {
                Ok(runtime) => runtime,
                Err(err) => {
                    tracing::warn!("failed to start watcher runtime: {err:?}");
                    return;
                }
            };
            runtime.block_on(run(cancel_rx));
        })
        .expect("failed to spawn watcher runtime thread");

    WatchHandle::new_thread(cancel_tx, thread)
}
