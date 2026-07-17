#!/usr/bin/env bash
set -Eeuo pipefail
export AWS_PAGER=""

PROJECT_DIR="$HOME/opsai-assistant-aws"
WEB_DIR="$PROJECT_DIR/app/web"
ENV_FILE="$PROJECT_DIR/.env"

cd "$PROJECT_DIR"

[[ -f "$ENV_FILE" ]] || { echo "ERROR: $ENV_FILE was not found."; exit 1; }
[[ -f "$WEB_DIR/index.html" ]] || { echo "ERROR: index.html was not found."; exit 1; }

set -a
source "$ENV_FILE"
set +a

AWS_REGION="${AWS_REGION:-us-east-1}"
AMPLIFY_BRANCH_NAME="${AMPLIFY_BRANCH_NAME:-main}"

if [[ -z "${AMPLIFY_APP_ID:-}" ]]; then
  AMPLIFY_APP_ID="$(aws amplify list-apps \
    --region "$AWS_REGION" \
    --query "apps[?name=='opsai-assistant-ui'].appId | [0]" \
    --output text)"
fi

[[ -n "$AMPLIFY_APP_ID" && "$AMPLIFY_APP_ID" != "None" ]] || {
  echo "ERROR: Amplify application was not found."
  exit 1
}

DEFAULT_DOMAIN="$(aws amplify get-app \
  --app-id "$AMPLIFY_APP_ID" \
  --region "$AWS_REGION" \
  --query 'app.defaultDomain' \
  --output text)"

AMPLIFY_URL="${AMPLIFY_URL:-https://${AMPLIFY_BRANCH_NAME}.${DEFAULT_DOMAIN}}"

BACKUP_DIR="$PROJECT_DIR/backups/voice-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp "$WEB_DIR/index.html" "$BACKUP_DIR/index.html"

for file in opsai-voice.css opsai-voice.js; do
  [[ -f "$WEB_DIR/$file" ]] && cp "$WEB_DIR/$file" "$BACKUP_DIR/$file"
done

cat > "$WEB_DIR/opsai-voice.css" <<'CSSEOF'
.opsai-voice-button {
  display:inline-flex;width:42px;height:42px;align-items:center;justify-content:center;
  border:1px solid #bfdbfe;border-radius:13px;background:#eff6ff;color:#1d4ed8;
  font-size:19px;cursor:pointer;margin-right:7px
}
.opsai-voice-button:hover{background:#dbeafe}
.opsai-voice-button.listening{background:#fee2e2;color:#dc2626;animation:vPulse 1.2s infinite}
.opsai-voice-button:disabled{opacity:.5;cursor:not-allowed}
@keyframes vPulse{0%{box-shadow:0 0 0 0 rgba(239,68,68,.35)}70%{box-shadow:0 0 0 11px rgba(239,68,68,0)}100%{box-shadow:0 0 0 0 rgba(239,68,68,0)}}

.opsai-voice-overlay{
  position:fixed;inset:0;z-index:30000;display:none;align-items:center;justify-content:center;
  padding:20px;background:rgba(15,23,42,.48);backdrop-filter:blur(12px)
}
.opsai-voice-overlay.visible{display:flex}
.opsai-voice-dialog{
  width:min(500px,calc(100vw - 32px));padding:23px;border:1px solid #bfdbfe;
  border-radius:25px;background:linear-gradient(155deg,#fff,#eff6ff);
  box-shadow:0 30px 90px rgba(15,23,42,.3)
}
.opsai-voice-header{display:flex;justify-content:space-between;gap:12px}
.opsai-voice-header h2{margin:0;color:#0f172a;font-size:20px}
.opsai-voice-header p{margin:5px 0 0;color:#64748b;font-size:11px}
.opsai-voice-close{width:34px;height:34px;border:1px solid #cbd5e1;border-radius:10px;background:#fff;cursor:pointer}
.opsai-voice-orb-wrap{display:flex;justify-content:center;padding:25px 0 18px}
.opsai-voice-orb{
  display:grid;width:142px;height:142px;place-items:center;border-radius:50%;color:#fff;font-size:39px;
  background:radial-gradient(circle at 34% 28%,#93c5fd,transparent 28%),
             radial-gradient(circle at 70% 70%,#8b5cf6,transparent 38%),
             linear-gradient(145deg,#2563eb,#06b6d4);
  box-shadow:0 0 0 12px rgba(59,130,246,.08),0 28px 60px rgba(37,99,235,.28)
}
.opsai-voice-orb.listening{animation:orb 1.25s infinite}
.opsai-voice-orb.speaking{animation:orb .8s infinite}
@keyframes orb{50%{transform:scale(1.05)}}
.opsai-voice-status{margin:0;min-height:20px;text-align:center;color:#1e3a8a;font-size:13px;font-weight:800}
.opsai-voice-text{min-height:65px;margin-top:11px;padding:12px;border:1px solid #dbeafe;border-radius:12px;background:#fff;color:#334155;font-size:12px;line-height:1.5}
.opsai-voice-controls,.opsai-voice-settings{display:grid;grid-template-columns:1fr 1fr;gap:9px;margin-top:12px}
.opsai-voice-controls button,.opsai-voice-settings select{min-height:40px;border-radius:10px;font-size:11px;font-weight:800}
.opsai-voice-start{border:0;background:linear-gradient(135deg,#2563eb,#4f46e5);color:#fff;cursor:pointer}
.opsai-voice-stop{border:1px solid #cbd5e1;background:#fff;color:#334155;cursor:pointer}
.opsai-voice-settings label{font-size:9px;font-weight:800;color:#475569}
.opsai-voice-settings select{width:100%;margin-top:5px;padding:0 9px;border:1px solid #cbd5e1;background:#fff}
.opsai-voice-switch{display:flex;align-items:center;justify-content:space-between;gap:10px;margin-top:10px;padding:10px;border:1px solid #dbeafe;border-radius:10px;background:#eff6ff;color:#334155;font-size:10px}
.opsai-read-aloud{display:inline-flex;margin-top:7px;padding:5px 8px;border:1px solid #dbeafe;border-radius:999px;background:#eff6ff;color:#1d4ed8;font-size:9px;font-weight:800;cursor:pointer}
.opsai-voice-note{margin:10px 0 0;color:#64748b;font-size:9px;text-align:center;line-height:1.45}
@media(max-width:600px){.opsai-voice-controls,.opsai-voice-settings{grid-template-columns:1fr}.opsai-voice-orb{width:120px;height:120px}}
CSSEOF

cat > "$WEB_DIR/opsai-voice.js" <<'JSEOF'
(() => {
  const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  const canRecognize = Boolean(Recognition);
  const canSpeak = 'speechSynthesis' in window && 'SpeechSynthesisUtterance' in window;
  const KEY = 'opsai-voice-settings-v2';

  let recognition;
  let listening = false;
  let speaking = false;
  let open = false;
  let waiting = false;
  let transcript = '';
  let lastAnswer = '';
  let restartTimer;

  const settings = (() => {
    try {
      return {
        language: 'en-IN',
        voice: '',
        autoSend: true,
        continueAfterAnswer: false,
        ...JSON.parse(localStorage.getItem(KEY) || '{}')
      };
    } catch {
      return {language:'en-IN', voice:'', autoSend:true, continueAfterAnswer:false};
    }
  })();

  const save = () => localStorage.setItem(KEY, JSON.stringify(settings));

  function composer(){ return document.querySelector('.composer-area'); }
  function input(){
    const c = composer();
    return c && (c.querySelector('textarea[placeholder*="Ask OpsAI"]') ||
      c.querySelector('textarea') || c.querySelector('input[placeholder*="Ask OpsAI"]') ||
      c.querySelector('input[type="text"]'));
  }
  function send(){
    const c = composer();
    if (!c) return null;
    return c.querySelector('button[type="submit"]') ||
      [...c.querySelectorAll('button')].find(b =>
        /send|submit|➤|→/i.test(`${b.textContent} ${b.ariaLabel || ''} ${b.title || ''}`)) ||
      c.querySelector('button:last-of-type');
  }
  function setValue(el, value){
    const p = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    const d = Object.getOwnPropertyDescriptor(p, 'value');
    d?.set ? d.set.call(el, value) : el.value = value;
    el.dispatchEvent(new Event('input', {bubbles:true}));
    el.dispatchEvent(new Event('change', {bubbles:true}));
  }
  function bubbles(){
    const selectors = [
      '.message-row.assistant .message-bubble',
      '.assistant .message-bubble',
      '[data-role="assistant"]',
      '.assistant-message',
      '.message.assistant'
    ];
    const found = [];
    const seen = new Set();
    selectors.forEach(s => document.querySelectorAll(s).forEach(el => {
      if (!seen.has(el)) { seen.add(el); found.push(el); }
    }));
    return found;
  }
  function bubbleText(el){
    if (!el) return '';
    const clone = el.cloneNode(true);
    clone.querySelectorAll('.opsai-read-aloud,button,script,style').forEach(n => n.remove());
    return String(clone.textContent || '').replace(/\s+/g,' ')
      .replace(/OpsAI Assistant\s*$/i,'').trim();
  }
  function latest(){ const list = bubbles(); return bubbleText(list.at(-1)); }

  function status(text){ const el = document.getElementById('opsai-voice-status'); if(el) el.textContent = text; }
  function display(text){ const el = document.getElementById('opsai-voice-text'); if(el) el.textContent = text; }
  function state(name){
    const orb = document.getElementById('opsai-voice-orb');
    const btn = document.getElementById('opsai-voice-button');
    if (!orb || !btn) return;
    orb.classList.toggle('listening', name === 'listening');
    orb.classList.toggle('speaking', name === 'speaking');
    btn.classList.toggle('listening', name === 'listening');
    orb.textContent = name === 'speaking' ? '🔊' : name === 'waiting' ? '✨' : '🎙️';
  }

  function create(){
    if (document.getElementById('opsai-voice-button')) return;
    const c = composer(), s = send();
    if (!c || !s) { setTimeout(create, 150); return; }

    const button = document.createElement('button');
    button.id = 'opsai-voice-button';
    button.className = 'opsai-voice-button';
    button.type = 'button';
    button.title = 'Voice mode';
    button.ariaLabel = 'Open OpsAI voice mode';
    button.textContent = '🎙️';
    if (!canRecognize) {
      button.disabled = true;
      button.title = 'Use Google Chrome for microphone voice recognition';
    }
    s.insertAdjacentElement('beforebegin', button);

    const overlay = document.createElement('div');
    overlay.id = 'opsai-voice-overlay';
    overlay.className = 'opsai-voice-overlay';
    overlay.innerHTML = `
      <section class="opsai-voice-dialog" role="dialog" aria-modal="true">
        <div class="opsai-voice-header">
          <div><h2>OpsAI Voice</h2><p>Speak a question and hear the answer.</p></div>
          <button id="opsai-voice-close" class="opsai-voice-close" type="button">✕</button>
        </div>
        <div class="opsai-voice-orb-wrap"><div id="opsai-voice-orb" class="opsai-voice-orb">🎙️</div></div>
        <p id="opsai-voice-status" class="opsai-voice-status">Ready</p>
        <div id="opsai-voice-text" class="opsai-voice-text">Click Start listening and speak clearly.</div>
        <div class="opsai-voice-controls">
          <button id="opsai-voice-start" class="opsai-voice-start" type="button">Start listening</button>
          <button id="opsai-voice-stop" class="opsai-voice-stop" type="button">Stop</button>
        </div>
        <div class="opsai-voice-settings">
          <label>Language
            <select id="opsai-voice-language">
              <option value="en-IN">English — India</option>
              <option value="en-US">English — US</option>
              <option value="en-GB">English — UK</option>
              <option value="hi-IN">Hindi — India</option>
              <option value="te-IN">Telugu — India</option>
            </select>
          </label>
          <label>Reading voice<select id="opsai-voice-select"><option value="">Browser default</option></select></label>
        </div>
        <label class="opsai-voice-switch"><span>Send automatically after speech</span><input id="opsai-voice-auto" type="checkbox"></label>
        <label class="opsai-voice-switch"><span>Continue listening after the answer</span><input id="opsai-voice-continue" type="checkbox"></label>
        <p class="opsai-voice-note">Allow microphone access. Use headphones for continuous conversation.</p>
      </section>`;
    document.body.appendChild(overlay);

    document.getElementById('opsai-voice-language').value = settings.language;
    document.getElementById('opsai-voice-auto').checked = settings.autoSend;
    document.getElementById('opsai-voice-continue').checked = settings.continueAfterAnswer;

    button.onclick = openMode;
    document.getElementById('opsai-voice-close').onclick = closeMode;
    document.getElementById('opsai-voice-start').onclick = startListening;
    document.getElementById('opsai-voice-stop').onclick = stopAll;
    overlay.onclick = e => { if (e.target === overlay) closeMode(); };

    document.getElementById('opsai-voice-language').onchange = e => {
      settings.language = e.target.value; save();
    };
    document.getElementById('opsai-voice-select').onchange = e => {
      settings.voice = e.target.value; save();
    };
    document.getElementById('opsai-voice-auto').onchange = e => {
      settings.autoSend = e.target.checked; save();
    };
    document.getElementById('opsai-voice-continue').onchange = e => {
      settings.continueAfterAnswer = e.target.checked; save();
    };

    populateVoices();
    addReadButtons();

    new MutationObserver(() => {
      addReadButtons();
      if (!waiting || speaking) return;
      const answer = latest();
      if (answer && answer !== lastAnswer && answer.length > 8) {
        waiting = false;
        lastAnswer = answer;
        display(answer);
        speak(answer, settings.continueAfterAnswer);
      }
    }).observe(document.body, {childList:true, subtree:true, characterData:true});
  }

  function openMode(){
    if (!canRecognize) {
      alert('Voice recognition is not available. Use the latest Google Chrome and allow microphone access.');
      return;
    }
    open = true;
    lastAnswer = latest();
    document.getElementById('opsai-voice-overlay').classList.add('visible');
    status('Ready');
    display('Click Start listening and speak clearly.');
  }
  function closeMode(){
    open = false; waiting = false; stopAll();
    document.getElementById('opsai-voice-overlay')?.classList.remove('visible');
  }

  function buildRecognition(){
    const r = new Recognition();
    r.lang = settings.language;
    r.continuous = false;
    r.interimResults = true;
    r.maxAlternatives = 1;

    r.onstart = () => {
      listening = true; transcript = ''; status('Listening...'); display('Speak now.'); state('listening');
    };
    r.onresult = e => {
      let interim = '';
      for (let i=e.resultIndex;i<e.results.length;i++){
        const text = e.results[i][0]?.transcript || '';
        e.results[i].isFinal ? transcript += text : interim += text;
      }
      const text = `${transcript} ${interim}`.replace(/\s+/g,' ').trim();
      if (text) display(text);
    };
    r.onerror = e => {
      listening = false; state('idle');
      const m = {
        'not-allowed':'Microphone permission was denied. Allow it from the address bar.',
        'no-speech':'No speech was detected. Try again.',
        'audio-capture':'No microphone was detected.',
        'network':'The browser speech service had a network problem.',
        'aborted':'Listening stopped.'
      };
      status(m[e.error] || `Voice error: ${e.error}`);
    };
    r.onend = () => {
      listening = false; state('idle');
      const text = transcript.replace(/\s+/g,' ').trim();
      if (!text) { if(open) status('Ready'); return; }
      display(text);
      settings.autoSend ? submit(text) : insert(text);
    };
    return r;
  }

  function startListening(){
    if (!open || listening) return;
    stopSpeaking();
    transcript = '';
    recognition = buildRecognition();
    try { recognition.start(); }
    catch { status('Wait a moment and try again.'); }
  }
  function stopListening(){
    clearTimeout(restartTimer);
    if (recognition && listening) {
      try { recognition.stop(); } catch {}
    }
    listening = false; state('idle');
  }
  function insert(text){
    const el = input();
    if (!el) { status('Message box was not found.'); return; }
    setValue(el, text); el.focus(); status('Added to the message box. Press Send.');
  }
  function submit(text){
    stopListening();
    const el = input(), btn = send();
    if (!el || !btn) { status('Message box or Send button was not found.'); return; }
    lastAnswer = latest(); waiting = true; setValue(el, text); status('Sending to OpsAI...'); state('waiting');
    setTimeout(() => {
      btn.click();
      setTimeout(() => {
        if (el.value.trim()) {
          el.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',code:'Enter',bubbles:true}));
        }
      },180);
    },100);
  }

  function clean(text){
    return String(text || '').replace(/```[\s\S]*?```/g,' Code block omitted. ')
      .replace(/`([^`]+)`/g,'$1').replace(/https?:\/\/\S+/g,' link ')
      .replace(/[*#_>|~]/g,' ').replace(/\s+/g,' ').trim();
  }
  function voice(){
    const voices = speechSynthesis.getVoices();
    return voices.find(v => v.name === settings.voice) ||
      voices.find(v => v.lang === settings.language) ||
      voices.find(v => v.lang.startsWith(settings.language.split('-')[0])) || null;
  }
  function speak(text, restart=false){
    if (!canSpeak) { status('Text-to-speech is not supported.'); return; }
    const value = clean(text); if (!value) return;
    stopListening(); stopSpeaking();
    const u = new SpeechSynthesisUtterance(value);
    u.lang = settings.language; u.rate = 1; u.pitch = 1; u.volume = 1;
    const selected = voice(); if (selected) u.voice = selected;
    u.onstart = () => { speaking=true; status('OpsAI is speaking...'); state('speaking'); };
    u.onend = () => {
      speaking=false; state('idle');
      if (open && restart) {
        status('Listening will resume...');
        restartTimer = setTimeout(startListening,650);
      } else if (open) status('Ready');
    };
    u.onerror = () => { speaking=false; state('idle'); status('Unable to read the answer.'); };
    speechSynthesis.speak(u);
  }
  function stopSpeaking(){ if(canSpeak) speechSynthesis.cancel(); speaking=false; }
  function stopAll(){ waiting=false; stopListening(); stopSpeaking(); if(open) status('Stopped'); }

  function populateVoices(){
    if (!canSpeak) return;
    const select = document.getElementById('opsai-voice-select');
    if (!select) return;
    const voices = speechSynthesis.getVoices();
    select.innerHTML = '<option value="">Browser default</option>' +
      voices.map(v => `<option value="${escape(v.name)}" ${v.name===settings.voice?'selected':''}>${escape(v.name)} — ${escape(v.lang)}</option>`).join('');
  }
  function escape(value){
    return String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));
  }
  function addReadButtons(){
    bubbles().forEach(b => {
      if (b.querySelector('.opsai-read-aloud')) return;
      const btn = document.createElement('button');
      btn.type='button'; btn.className='opsai-read-aloud'; btn.textContent='🔊 Read aloud';
      btn.onclick = () => speaking ? stopSpeaking() : speak(bubbleText(b));
      b.appendChild(btn);
    });
  }

  if (canSpeak) speechSynthesis.addEventListener('voiceschanged', populateVoices);
  document.readyState === 'loading'
    ? document.addEventListener('DOMContentLoaded', create, {once:true})
    : create();
})();
JSEOF

python3 - <<'PY'
from pathlib import Path
import re, time

p = Path.home() / "opsai-assistant-aws/app/web/index.html"
text = p.read_text(encoding="utf-8")
v = str(int(time.time()))

text = re.sub(r'\s*<link[^>]+opsai-voice\.css[^>]*>\s*', '\n', text, flags=re.I)
text = re.sub(r'\s*<script[^>]+opsai-voice\.js[^>]*>\s*</script>\s*', '\n', text, flags=re.I)

if "</head>" not in text or "</body>" not in text:
    raise SystemExit("ERROR: index.html is missing closing head or body tags.")

text = text.replace("</head>", f'  <link rel="stylesheet" href="opsai-voice.css?v={v}">\n</head>', 1)
text = text.replace("</body>", f'  <script src="opsai-voice.js?v={v}"></script>\n</body>', 1)
p.write_text(text, encoding="utf-8")
print(f"Voice files linked with version {v}.")
PY

node --check "$WEB_DIR/opsai-voice.js"
grep -q "SpeechRecognition" "$WEB_DIR/opsai-voice.js"
grep -q "SpeechSynthesisUtterance" "$WEB_DIR/opsai-voice.js"
grep -q "Read aloud" "$WEB_DIR/opsai-voice.js"
grep -q "opsai-voice.css" "$WEB_DIR/index.html"
grep -q "opsai-voice.js" "$WEB_DIR/index.html"

echo "Voice validation passed."

rm -f "$PROJECT_DIR/app/opsai-assistant-ui.zip"
(
  cd "$WEB_DIR"
  zip -qr ../opsai-assistant-ui.zip .
)

DEPLOYMENT_OUTPUT="$(aws amplify create-deployment \
  --app-id "$AMPLIFY_APP_ID" \
  --branch-name "$AMPLIFY_BRANCH_NAME" \
  --region "$AWS_REGION" \
  --output json)"

JOB_ID="$(echo "$DEPLOYMENT_OUTPUT" | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["jobId"])')"

UPLOAD_URL="$(echo "$DEPLOYMENT_OUTPUT" | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["zipUploadUrl"])')"

curl -sS --upload-file "$PROJECT_DIR/app/opsai-assistant-ui.zip" "$UPLOAD_URL"

aws amplify start-deployment \
  --app-id "$AMPLIFY_APP_ID" \
  --branch-name "$AMPLIFY_BRANCH_NAME" \
  --job-id "$JOB_ID" \
  --region "$AWS_REGION" \
  >/dev/null

while true; do
  STATUS="$(aws amplify get-job \
    --app-id "$AMPLIFY_APP_ID" \
    --branch-name "$AMPLIFY_BRANCH_NAME" \
    --job-id "$JOB_ID" \
    --region "$AWS_REGION" \
    --query 'job.summary.status' \
    --output text)"

  echo "Deployment status: $STATUS"

  case "$STATUS" in
    SUCCEED) break ;;
    FAILED|CANCELLED) echo "ERROR: Amplify deployment failed."; exit 1 ;;
    *) sleep 10 ;;
  esac
done

echo
echo "============================================================"
echo "OpsAI voice assistant deployed successfully."
echo "============================================================"
echo "URL: $AMPLIFY_URL"
echo "Use Google Chrome, allow microphone access, and press Ctrl + Shift + R."
