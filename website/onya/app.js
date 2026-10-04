'use strict';

// A deterministic explanatory model. No Bluetooth, network, storage or user data.
const simulation = document.querySelector('.simulation');
const statusText = document.getElementById('sim-status');
const stepLabel = document.getElementById('sim-step-label');
const requesterPanel = document.getElementById('requester-panel');
const helperPanel = document.getElementById('helper-panel');
const requesterTitle = document.getElementById('requester-title');
const helperTitle = document.getElementById('helper-title');
const requesterSubtitle = document.getElementById('requester-subtitle');
const helperSubtitle = document.getElementById('helper-subtitle');
const buttons = {
  discover: document.getElementById('discover-button'),
  request: document.getElementById('request-button'),
  accept: document.getElementById('accept-button'),
  reject: document.getElementById('reject-button'),
  chat: document.getElementById('chat-button'),
  restart: document.getElementById('restart-button'),
};
const initialRequester = requesterPanel.innerHTML;
const initialHelper = helperPanel.innerHTML;
let state = 'available';

// Only fixed, authored HTML is used for explanatory panels; no input is inserted.
const panels = {
  discovered: '<span class="sim-person">J</span><p class="panel-heading">Jamie is nearby.</p><p class="panel-description">Open to helping.<br>A connection needs their approval.</p><span class="availability-pill"><span class="signal-dot" aria-hidden="true"></span> Available</span>',
  waiting: '<span class="sim-person">J</span><p class="panel-heading">Request sent.</p><p class="panel-description">Waiting for Jamie’s choice.<br>Chat is not open yet.</p><span class="connection-status">AWAITING APPROVAL</span>',
  requested: '<span class="sim-person requester">A</span><p class="panel-heading">Alex wants to connect.</p><p class="panel-description">You can accept or reject.<br>You don’t have to help.</p><span class="connection-status">YOUR CHOICE</span>',
  accepted: '<div class="availability-orbit" aria-hidden="true"><span>✓</span></div><p class="panel-heading">Connection accepted.</p><p class="panel-description">Both people can now exchange text.</p><span class="connection-status">CHAT IS READY</span>',
  rejected: '<p class="panel-heading">No connection this time.</p><p class="panel-description">Jamie declined the request.<br>No chat has started.</p><span class="connection-status">REQUEST CLOSED</span>',
};
const messages = [
  { sender: 'alex', text: 'Hi! Campus Wi-Fi dropped. Do you know where the library help desk is?' },
  { sender: 'jamie', text: 'Hey! It’s just inside the main entrance. Happy to point you there.' },
  { sender: 'alex', text: 'That helps. Good on ya!' },
];

function showChat(side, element) {
  element.replaceChildren();
  const caption = document.createElement('p');
  caption.className = 'chat-caption';
  caption.textContent = 'ILLUSTRATIVE CONVERSATION';
  element.append(caption);
  for (const message of messages) {
    const bubble = document.createElement('p');
    bubble.className = `chat-bubble${message.sender === side ? ' mine' : ''}`;
    bubble.textContent = message.text;
    element.append(bubble);
  }
}

function render(focusNext = true) {
  simulation.dataset.state = state;
  const states = ['available', 'discovered', 'requested', 'accepted', 'chat'];
  const activeIndex = states.indexOf(state === 'rejected' ? 'requested' : state);
  for (const item of document.querySelectorAll('[data-step]')) {
    const index = states.indexOf(item.dataset.step);
    item.classList.toggle('current', index === activeIndex);
    item.classList.toggle('complete', index < activeIndex);
    if (index === activeIndex) item.setAttribute('aria-current', 'step');
    else item.removeAttribute('aria-current');
  }
  for (const button of Object.values(buttons)) button.hidden = true;
  const requesterChat = document.getElementById('requester-chat');
  const helperChat = document.getElementById('helper-chat');
  requesterChat.hidden = helperChat.hidden = state !== 'chat';
  requesterPanel.hidden = helperPanel.hidden = state === 'chat';
  requesterTitle.textContent = 'A little help?';
  helperTitle.textContent = 'Open to helping.';
  requesterSubtitle.textContent = 'Find someone nearby who’s open to helping.';
  helperSubtitle.textContent = 'You choose when to connect.';
  let next;

  switch (state) {
    case 'available':
      requesterPanel.innerHTML = initialRequester;
      helperPanel.innerHTML = initialHelper;
      stepLabel.textContent = 'STEP 01 / AVAILABLE';
      statusText.textContent = 'Jamie is available. Alex can look for a nearby helper.';
      next = buttons.discover;
      break;
    case 'discovered':
      requesterPanel.innerHTML = panels.discovered;
      helperPanel.innerHTML = initialHelper;
      stepLabel.textContent = 'STEP 02 / DISCOVERED';
      statusText.textContent = 'Alex has found Jamie nearby. Discovery does not start a conversation.';
      next = buttons.request;
      break;
    case 'requested':
      requesterPanel.innerHTML = panels.waiting;
      helperPanel.innerHTML = panels.requested;
      stepLabel.textContent = 'STEP 03 / CONNECTION REQUESTED';
      statusText.textContent = 'Alex sent a request. Jamie decides whether to accept. No chat is available yet.';
      buttons.reject.hidden = false;
      next = buttons.accept;
      break;
    case 'accepted':
      requesterPanel.innerHTML = helperPanel.innerHTML = panels.accepted;
      stepLabel.textContent = 'STEP 04 / ACCEPTED';
      statusText.textContent = 'Jamie accepted this connection. Now the two people can exchange text.';
      next = buttons.chat;
      break;
    case 'chat':
      requesterTitle.textContent = 'Chat with Jamie';
      helperTitle.textContent = 'Chat with Alex';
      requesterSubtitle.textContent = helperSubtitle.textContent = 'This conversation follows explicit acceptance.';
      showChat('alex', requesterChat);
      showChat('jamie', helperChat);
      stepLabel.textContent = 'STEP 05 / CHAT';
      statusText.textContent = 'An approved conversation. This fictional chat illustrates asking for nearby help.';
      next = buttons.restart;
      break;
    case 'rejected':
      requesterPanel.innerHTML = panels.rejected;
      helperPanel.innerHTML = initialHelper;
      stepLabel.textContent = 'REQUEST REJECTED / NO CHAT';
      statusText.textContent = 'Jamie rejected the request. Alex cannot start this chat. Helping remains voluntary.';
      next = buttons.restart;
      break;
  }
  next.hidden = false;
  if (focusNext) next.focus({ preventScroll: true });
}

function transition(expected, target) {
  if (state !== expected) return;
  state = target;
  render();
}
buttons.discover.addEventListener('click', () => transition('available', 'discovered'));
buttons.request.addEventListener('click', () => transition('discovered', 'requested'));
buttons.accept.addEventListener('click', () => transition('requested', 'accepted'));
buttons.reject.addEventListener('click', () => transition('requested', 'rejected'));
buttons.chat.addEventListener('click', () => transition('accepted', 'chat'));
function reset() {
  state = 'available';
  for (const element of document.querySelectorAll('.chat-messages')) element.replaceChildren();
  render();
}
buttons.restart.addEventListener('click', reset);
document.getElementById('reset-simulation').addEventListener('click', reset);
render(false);

// Without JavaScript both platform descriptions remain readable.
const platformPicker = document.querySelector('.platform-picker');
const platformButtons = [document.getElementById('choose-android'), document.getElementById('choose-ios')];
function choosePlatform(platform) {
  for (const button of platformButtons) {
    const selected = button.id === `choose-${platform}`;
    button.setAttribute('aria-pressed', String(selected));
    button.classList.toggle('button-primary', selected);
    button.classList.toggle('button-outline', !selected);
    document.getElementById(button.getAttribute('aria-controls')).hidden = !selected;
  }
}
platformPicker.hidden = false;
platformButtons[0].addEventListener('click', () => choosePlatform('android'));
platformButtons[1].addEventListener('click', () => choosePlatform('ios'));
choosePlatform('android');

// Distribution links are optional. No request, embedding or download occurs here.
const releases = window.ONYA_RELEASES;
function safeHttpsUrl(value) {
  if (typeof value !== 'string') return null;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && !url.username && !url.password && !url.port ? url : null;
  } catch {
    return null;
  }
}
const apk = safeHttpsUrl(releases?.android?.url);
const version = releases?.android?.version;
const sourceCommit = releases?.android?.sourceCommit;
if (apk && apk.hostname === 'github.com' &&
    /^\/Laxmi-Srinivas\/Offline-relay\/releases\/download\/[^/]+\/[^/]+\.apk$/i.test(apk.pathname) &&
    typeof version === 'string' && version.trim() &&
    typeof sourceCommit === 'string' && /^[0-9a-f]{40}$/i.test(sourceCommit)) {
  const link = document.getElementById('android-download');
  link.href = apk.href;
  link.hidden = false;
  document.getElementById('android-download-status').textContent = 'Try the Android beta.';
  document.getElementById('android-version').textContent = `Version ${version.trim()} · Android beta`;
  const source = document.getElementById('android-source');
  source.textContent = `APK source commit: ${sourceCommit}`;
  source.hidden = false;
}
const demo = safeHttpsUrl(releases?.iphoneDemo?.url);
if (demo) {
  const link = document.getElementById('iphone-demo');
  link.href = demo.href;
  link.hidden = false;
}
