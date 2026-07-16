(() => {
  const frame = document.querySelector('#gameFrame');
  const stage = document.querySelector('#gameStage');
  const shell = document.querySelector('.app-shell');
  const startPanel = document.querySelector('#startPanel');
  const loadingPanel = document.querySelector('#loadingPanel');
  const startButton = document.querySelector('#startButton');
  const startButtonLabel = startButton.querySelector('span');
  const startFeedback = document.querySelector('#startFeedback');
  const fullscreenButton = document.querySelector('#fullscreenButton');
  const runtimeStatus = document.querySelector('#runtimeStatus');
  const loadingMessage = loadingPanel.querySelector('span');
  const loadingProgress = document.querySelector('#loadingProgress');
  const engineMessageSource = 'riding-dirty-game';
  const startupTimeoutMs = 45000;
  let gameRequested = false;
  let engineSettled = false;
  let startupTimer = null;
  let startAttempt = 0;

  const clearStartupTimer = () => {
    if (startupTimer !== null) {
      window.clearTimeout(startupTimer);
      startupTimer = null;
    }
  };

  const showStartFailure = (message) => {
    clearStartupTimer();
    gameRequested = false;
    engineSettled = true;
    loadingPanel.hidden = true;
    loadingPanel.setAttribute('aria-busy', 'false');
    startFeedback.textContent = message;
    startFeedback.hidden = false;
    startButtonLabel.textContent = 'RETRY THE TOUR';
    startPanel.hidden = false;
    runtimeStatus.textContent = 'ENGINE FAILED · RETRY AVAILABLE';
    startButton.focus();
  };

  const startGame = () => {
    if (gameRequested && !engineSettled) return;
    clearStartupTimer();
    startAttempt += 1;
    gameRequested = true;
    engineSettled = false;
    startFeedback.hidden = true;
    startFeedback.textContent = '';
    startButtonLabel.textContent = 'START THE TOUR';
    startPanel.hidden = true;
    loadingPanel.hidden = false;
    loadingPanel.setAttribute('aria-busy', 'true');
    loadingMessage.textContent = 'Loading the WebAssembly build…';
    loadingProgress.hidden = true;
    loadingProgress.removeAttribute('value');
    stage.classList.add('is-running');
    shell.classList.add('is-playing');
    runtimeStatus.textContent = 'LOADING BUILD';
    const separator = frame.dataset.src.includes('?') ? '&' : '?';
    frame.src = `${frame.dataset.src}${separator}attempt=${startAttempt}`;
    startupTimer = window.setTimeout(() => {
      if (gameRequested && !engineSettled) {
        showStartFailure('The engine took too long to start. Check the connection, then retry.');
      }
    }, startupTimeoutMs);
  };

  startButton.addEventListener('click', startGame);

  frame.addEventListener('load', () => {
    if (!gameRequested || engineSettled) return;
    runtimeStatus.textContent = 'STARTING ENGINE';
    frame.focus();
  });

  window.addEventListener('message', (event) => {
    if (!gameRequested) return;
    if (event.origin !== window.location.origin || event.source !== frame.contentWindow) return;
    if (!event.data || event.data.source !== engineMessageSource) return;
    if (event.data.type === 'engine-ready') {
      clearStartupTimer();
      engineSettled = true;
      loadingPanel.hidden = true;
      loadingPanel.setAttribute('aria-busy', 'false');
      runtimeStatus.textContent = 'ENGINE ONLINE';
      frame.focus();
    } else if (event.data.type === 'engine-error') {
      showStartFailure('The game engine could not start. Retry, or confirm this host supports cross-origin isolation.');
    } else if (event.data.type === 'engine-progress') {
      const current = Number(event.data.current);
      const total = Number(event.data.total);
      if (Number.isFinite(current) && Number.isFinite(total) && current > 0 && total > 0) {
        const percent = Math.max(0, Math.min(100, Math.round((current / total) * 100)));
        loadingProgress.hidden = false;
        loadingProgress.value = percent;
        loadingMessage.textContent = `Loading engine assets… ${percent}%`;
        runtimeStatus.textContent = `LOADING BUILD · ${percent}%`;
      }
    }
  });

  frame.addEventListener('error', () => {
    if (gameRequested && !engineSettled) {
      showStartFailure('The game frame failed to load. Check the connection, then retry.');
    }
  });

  stage.addEventListener('pointerdown', () => frame.focus());

  fullscreenButton.addEventListener('click', async () => {
    try {
      if (document.fullscreenElement) {
        await document.exitFullscreen();
      } else {
        await stage.requestFullscreen();
      }
    } catch (error) {
      runtimeStatus.textContent = 'FULLSCREEN UNAVAILABLE';
    }
  });

  document.addEventListener('fullscreenchange', () => {
    const isFullscreen = Boolean(document.fullscreenElement);
    fullscreenButton.setAttribute('aria-label', isFullscreen ? 'Exit fullscreen' : 'Enter fullscreen');
    const label = fullscreenButton.querySelector('span');
    if (label) label.textContent = isFullscreen ? 'Exit fullscreen' : 'Fullscreen';
  });

})();
