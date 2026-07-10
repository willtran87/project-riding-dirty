(() => {
  const frame = document.querySelector('#gameFrame');
  const stage = document.querySelector('#gameStage');
  const startPanel = document.querySelector('#startPanel');
  const loadingPanel = document.querySelector('#loadingPanel');
  const startButton = document.querySelector('#startButton');
  const fullscreenButton = document.querySelector('#fullscreenButton');
  const runtimeStatus = document.querySelector('#runtimeStatus');

  const startGame = () => {
    startPanel.hidden = true;
    loadingPanel.hidden = false;
    stage.classList.add('is-running');
    runtimeStatus.textContent = 'LOADING BUILD';
    frame.src = frame.dataset.src;
  };

  startButton.addEventListener('click', startGame, { once: true });

  frame.addEventListener('load', () => {
    loadingPanel.hidden = true;
    runtimeStatus.textContent = 'ENGINE ONLINE';
    frame.focus();
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
    fullscreenButton.setAttribute('aria-label', document.fullscreenElement ? 'Exit fullscreen' : 'Enter fullscreen');
  });

  window.addEventListener('keydown', (event) => {
    if (['Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(event.code)) {
      event.preventDefault();
    }
  }, { passive: false });
})();
