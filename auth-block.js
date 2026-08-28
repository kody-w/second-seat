/* ── Auth: the same front door as Heimdall ────────────────────────────────────
   GitHub OAuth DEVICE-CODE flow (not the web flow), proxied through the estate's
   auth worker because github.com's device endpoints send no CORS headers to a
   Pages origin. Identical constants and identical storage shape to
   kody-w/heimdall's doorman, and the token lives under the shared `rapp_settings`
   key — same origin as every other front door on kody-w.github.io, so signing in
   here signs you in there and vice versa.

   The worker's Access-Control-Allow-Origin is pinned to https://kody-w.github.io.
   That is why this page is served from there: an artifact iframe could not do
   this at all (its CSP blocks fetch), and any other origin is refused by the
   worker. Served from anywhere else, sign-in fails and says so. */
const AUTH_WORKER_URL   = "https://rapp-auth.kwildfeuer.workers.dev";
const COPILOT_CLIENT_ID = "Iv1.b507a08c87ecfe98";
const STORAGE_KEY       = "rapp_settings";

function loadSettings(){ try { return JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}"); }
                         catch (e){ return {}; } }
function saveSettings(patch){
  try {
    var s = Object.assign(loadSettings(), patch);
    localStorage.setItem(STORAGE_KEY, JSON.stringify(s));
    return s;
  } catch (e){ return {}; }
}
function getToken(){ return loadSettings().ghuToken || null; }

var pendingDeviceLogin = null;

async function startDeviceLogin(){
  const r = await fetch(AUTH_WORKER_URL + "/api/auth/device", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ client_id: COPILOT_CLIENT_ID, scope: "read:user" })
  });
  if (!r.ok) throw new Error("device start " + r.status);
  const d = await r.json();
  // Never trust a network-supplied number straight into a timer.
  const iv = Number(d.interval);
  pendingDeviceLogin = {
    device_code: d.device_code,
    interval: (isFinite(iv) && iv >= 1 && iv <= 60) ? iv : 5,
    expires_at: Date.now() + (Number(d.expires_in) > 0 ? Number(d.expires_in) : 900) * 1000
  };
  return { user_code: d.user_code, verification_uri: d.verification_uri };
}

async function pollDeviceLogin(){
  if (!pendingDeviceLogin) return null;
  const r = await fetch(AUTH_WORKER_URL + "/api/auth/device/poll", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ device_code: pendingDeviceLogin.device_code,
                           client_id: COPILOT_CLIENT_ID })
  });
  if (!r.ok){
    // A transient 5xx/network blip must not kill an otherwise valid 15-minute
    // sign-in; keep waiting and let expiry be the only clock that ends it.
    return null;
  }
  const d = await r.json();
  if (d.access_token){
    saveSettings({ ghuToken: d.access_token });
    pendingDeviceLogin = null;
    return d.access_token;
  }
  // RFC 8628 §3.5: slow_down means lengthen the interval by at least 5s.
  if (d.error === "slow_down"){
    pendingDeviceLogin.interval = Math.min(60, pendingDeviceLogin.interval + 5);
    return "SLOW_DOWN";
  }
  if (d.error === "authorization_pending") return null;
  if (d.error){ pendingDeviceLogin = null; throw new Error(d.error_description || d.error); }
  return null;
}

function safeGitHubUrl(u){
  // A verification_uri arrives over the network. Only GitHub, only https.
  try {
    const p = new URL(String(u));
    if (p.protocol !== "https:") return null;
    if (p.hostname !== "github.com" && p.hostname !== "www.github.com") return null;
    return p.href;
  } catch (e){ return null; }
}

async function fetchAndCacheUser(token){
  try {
    const r = await fetch("https://api.github.com/user", {
      headers: { "Authorization": "Bearer " + token, "Accept": "application/vnd.github+json" }
    });
    if (!r.ok) return null;
    const u = await r.json();
    if (u.login){ saveSettings({ ghUser: { login: u.login, avatar: u.avatar_url || "" } }); return u; }
  } catch (e){}
  return null;
}

var PILOT = (loadSettings().ghUser || {}).login || null;
window.PILOT_NAME = PILOT;

function paintAuth(){
  var authBtn = document.getElementById('authBtn');
  var whoEl   = document.getElementById('who');
  if (PILOT){
    whoEl.hidden = false;
    whoEl.textContent = '@' + PILOT + ' in the seat';
    authBtn.textContent = 'Sign out';
  } else {
    whoEl.hidden = true;
    authBtn.textContent = 'Sign in with GitHub';
  }
}

document.getElementById('authBtn').addEventListener('click', async function(){
  var authBtn = document.getElementById('authBtn');
  if (PILOT || getToken()){
    saveSettings({ ghuToken: "", ghUser: null });
    PILOT = null; window.PILOT_NAME = null; paintAuth();
    if (window.SS_say) window.SS_say('Signed out. The logbook stays — it belongs to this browser, not to the account.');
    return;
  }
  var poller = null;
  try {
    authBtn.disabled = true;
    authBtn.textContent = 'Starting…';
    var d = await startDeviceLogin();
    var uri = safeGitHubUrl(d.verification_uri);
    if (!uri) throw new Error('the sign-in URL did not come from github.com');

    // The tab is NOT opened here: this runs after an await, so the gesture is
    // spent and the popup is blocked. Offer a link the person clicks instead.
    authBtn.disabled = false;
    authBtn.textContent = 'Code ' + d.user_code;
    var link = document.getElementById('authLink');
    link.href = uri;
    link.textContent = 'Enter ' + d.user_code + ' at github.com/login/device';
    link.hidden = false;
    if (window.SS_say) window.SS_say('Enter code ' + d.user_code + ' at ' + uri + ' — this page is waiting.');

    var schedule = function(){
      if (poller) clearTimeout(poller);
      poller = setTimeout(step, pendingDeviceLogin.interval * 1000);
    };
    var stop = function(msg){
      if (poller) clearTimeout(poller);
      poller = null;
      pendingDeviceLogin = null;
      link.hidden = true;
      authBtn.disabled = false;
      paintAuth();
      if (msg && window.SS_say) window.SS_say(msg);
    };
    var step = async function(){
      if (!pendingDeviceLogin) return;
      if (Date.now() > pendingDeviceLogin.expires_at){
        stop('That sign-in code expired. Start again when you like.');
        return;
      }
      try {
        var tok = await pollDeviceLogin();
        if (tok === "SLOW_DOWN"){ schedule(); return; }
        if (!tok){ schedule(); return; }
        if (poller) clearTimeout(poller);
        poller = null;
        link.hidden = true;
        var u = await fetchAndCacheUser(tok);
        // Signed in even if the /user lookup fails — the token is what counts.
        PILOT = (u && u.login) ? u.login : ((loadSettings().ghUser || {}).login || null);
        window.PILOT_NAME = PILOT;
        authBtn.disabled = false;
        paintAuth();
        if (window.SS_say) window.SS_say(PILOT ? ('Signed in as @' + PILOT + '.') : 'Signed in.');
        if (window.SS_log) window.SS_log(PILOT ? ('@' + PILOT + ' took the second seat') : 'Signed in');
        if (window.SS_frame) window.SS_frame({ event:'signin', pilot: PILOT || 'unknown' });
      } catch (err){
        stop('Sign-in failed: ' + err.message);
      }
    };
    schedule();
  } catch (err){
    if (poller) clearTimeout(poller);
    authBtn.disabled = false;
    paintAuth();
    if (window.SS_say) window.SS_say('Could not start sign-in: ' + err.message);
  }
});

// A token shared from another front door on this origin signs you in here too,
// even though this page has never cached the user.
(async function resumeSharedSession(){
  if (PILOT) return;
  var tok = getToken();
  if (!tok) return;
  var u = await fetchAndCacheUser(tok);
  if (u && u.login){
    PILOT = u.login; window.PILOT_NAME = PILOT; paintAuth();
    if (window.SS_log) window.SS_log('@' + PILOT + ' signed in at another door');
  }
})();

paintAuth();
