let currentState = {
    inVehicle: false,
    modelName: "CRUISER",
    seatName: "Driver",
    speed: 0,
    stage: 0,
    pattern: 1,
    sirenOn: false,
    sirenMuted: true,
    takedowns: false,
    alleyLeft: false,
    alleyRight: false,
    wigwag: false,
    blackout: false,
    hazards: false,
    extras: []
};

let audioCtx = null;
let soundVolumeScale = 0.6;

function playSwitchClickSound(type = 'click') {
    try {
        if (!audioCtx) {
            audioCtx = new (window.AudioContext || window.webkitAudioContext)();
        }
        if (audioCtx.state === 'suspended') {
            audioCtx.resume();
        }
        const osc = audioCtx.createOscillator();
        const gain = audioCtx.createGain();
        osc.connect(gain);
        gain.connect(audioCtx.destination);

        const now = audioCtx.currentTime;
        const vol = Math.max(0.0, Math.min(1.0, soundVolumeScale));
        if (type === 'stage') {
            osc.type = 'triangle';
            osc.frequency.setValueAtTime(1400, now);
            osc.frequency.exponentialRampToValueAtTime(800, now + 0.038);
            gain.gain.setValueAtTime(0.09 * vol, now);
            gain.gain.exponentialRampToValueAtTime(0.001, now + 0.045);
            osc.start(now);
            osc.stop(now + 0.045);
        } else if (type === 'tone') {
            osc.type = 'sine';
            osc.frequency.setValueAtTime(1800, now);
            osc.frequency.exponentialRampToValueAtTime(2200, now + 0.03);
            gain.gain.setValueAtTime(0.08 * vol, now);
            gain.gain.exponentialRampToValueAtTime(0.001, now + 0.035);
            osc.start(now);
            osc.stop(now + 0.035);
        } else {
            osc.type = 'square';
            osc.frequency.setValueAtTime(900, now);
            osc.frequency.exponentialRampToValueAtTime(180, now + 0.025);
            gain.gain.setValueAtTime(0.06 * vol, now);
            gain.gain.exponentialRampToValueAtTime(0.001, now + 0.028);
            osc.start(now);
            osc.stop(now + 0.028);
        }
    } catch (e) {}
}

const resourceName = window.GetParentResourceName ? window.GetParentResourceName() : 'SpaceELS';

function postNUI(callbackName, data = {}) {
    return fetch(`https://${resourceName}/${callbackName}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data)
    }).catch(() => {});
}

const elsContainer = document.getElementById('els-container');
const vehModelEl = document.getElementById('veh-model-name');
const vehSeatEl = document.getElementById('veh-seat-name');

const btnMasterSiren = document.getElementById('btn-master-siren');
const btnCycleTone = document.getElementById('btn-cycle-tone');
const lblCurrentTone = document.getElementById('lbl-current-tone');
const btnSirenMute = document.getElementById('btn-siren-mute');
const btnAirhorn = document.getElementById('btn-airhorn');

const TONES_LIST = ['wail', 'yelp', 'priority', 'hilo'];

function updateUI(state) {
    if (!state) return;
    currentState = Object.assign({}, currentState, state);

    vehModelEl.textContent = (currentState.modelName || 'VEHICLE').toUpperCase();
    vehSeatEl.textContent = currentState.seatName || 'Driver';

    const stageSegment = document.querySelector('.stages-segment');
    if (stageSegment) {
        stageSegment.innerHTML = '';
        const offBtn = document.createElement('button');
        offBtn.className = `seg-btn ${currentState.stage === 0 ? 'active' : ''}`;
        offBtn.setAttribute('data-stage', '0');
        offBtn.id = 'stage-btn-0';
        offBtn.textContent = 'OFF';
        offBtn.addEventListener('click', () => {
            playSwitchClickSound('stage');
            currentState.stage = 0;
            updateUI(currentState);
            postNUI('toggleStage', { stage: 0 });
        });
        stageSegment.appendChild(offBtn);

        const availableStages = currentState.availableStages || [1, 2, 3];
        availableStages.forEach(s => {
            const stgBtn = document.createElement('button');
            stgBtn.className = `seg-btn ${currentState.stage === s ? 'active' : ''}`;
            stgBtn.setAttribute('data-stage', s.toString());
            stgBtn.id = `stage-btn-${s}`;
            stgBtn.textContent = s === 3 ? 'CODE 3' : `STG ${s}`;
            stgBtn.addEventListener('click', () => {
                playSwitchClickSound('stage');
                currentState.stage = s;
                updateUI(currentState);
                postNUI('toggleStage', { stage: s });
            });
            stageSegment.appendChild(stgBtn);
        });
    }

    if (btnMasterSiren) btnMasterSiren.classList.toggle('active', currentState.sirenOn && !currentState.sirenMuted);
    if (btnSirenMute) btnSirenMute.classList.toggle('active', currentState.sirenMuted);

    if (lblCurrentTone) {
        const curTone = (currentState.sirenTone || 'wail').toUpperCase();
        lblCurrentTone.textContent = curTone;
    }
}

btnMasterSiren?.addEventListener('click', () => {
    playSwitchClickSound('click');
    currentState.sirenOn = !currentState.sirenOn;
    if (currentState.sirenOn) currentState.sirenMuted = false;
    updateUI(currentState);
    postNUI('toggleSirenAudio', { state: currentState.sirenOn });
});

btnCycleTone?.addEventListener('click', () => {
    playSwitchClickSound('tone');
    const curTone = currentState.sirenTone || 'wail';
    let idx = TONES_LIST.indexOf(curTone);
    if (idx === -1) idx = 0;
    const nextTone = TONES_LIST[(idx + 1) % TONES_LIST.length];
    currentState.sirenTone = nextTone;
    updateUI(currentState);
    postNUI('setSirenTone', { tone: nextTone });
});

btnSirenMute?.addEventListener('click', () => {
    playSwitchClickSound('click');
    currentState.sirenMuted = !currentState.sirenMuted;
    if (!currentState.sirenMuted) currentState.sirenOn = true;
    updateUI(currentState);
    postNUI('toggleSirenMute', { state: currentState.sirenMuted });
});

btnAirhorn?.addEventListener('mousedown', () => {
    playSwitchClickSound('click');
    postNUI('triggerAirhorn', { blasting: true });
});
btnAirhorn?.addEventListener('mouseup', () => {
    postNUI('triggerAirhorn', { blasting: false });
});
btnAirhorn?.addEventListener('mouseleave', () => {
    postNUI('triggerAirhorn', { blasting: false });
});

document.getElementById('btn-close')?.addEventListener('click', () => {
    postNUI('close');
});

window.addEventListener('keydown', (e) => {
    if (activeRecordingButton) return;
    if (e.key === 'Escape' || e.code === 'Escape' || e.key === 'u' || e.key === 'U') {
        if (builderContainer && builderContainer.style.display !== 'none') {
            closeBuilderUI();
        } else {
            postNUI('close');
        }
    }
});

window.addEventListener('message', (event) => {
    const item = event.data;
    if (!item) return;

    if (item.action === 'open') {
        if (typeof item.soundVolume === 'number') {
            soundVolumeScale = item.soundVolume;
        }
        elsContainer.style.display = 'block';
        updateUI(item.data);
    } else if (item.action === 'close') {
        elsContainer.style.display = 'none';
    } else if (item.action === 'updateState') {
        updateUI(item.data);
    } else if (item.syncLiveInfo && item.seatName) {
        if (vehSeatEl) vehSeatEl.textContent = item.seatName;
    } else if (item.action === 'syncLiveInfo') {
        if (vehSeatEl && item.seatName) vehSeatEl.textContent = item.seatName;
    } else if (item.action === 'openBuilder') {
        openBuilderUI(item.data);
    } else if (item.action === 'closeBuilder') {
        closeBuilderUI();
    }
});

const builderContainer = document.getElementById('builder-container');
const builderModelName = document.getElementById('builder-model-name');
const builderStatusText = document.getElementById('builder-status-text');
const stg3SpeedSlider = document.getElementById('stg3-speed-slider');
const stg3SpeedVal = document.getElementById('stg3-speed-val');

let currentEditingModel = "police";
let vehicleInstalledExtras = [];
let activeInspectExtra = null;

let workingProfile = {
    speed: 75,
    sirenBank: "VEHICLES_HORNS_SIREN_1",
    stage1: null,
    stage2: null,
    stage3: null,
    takedown: [],
    alleyLeft: [],
    alleyRight: [],
    labels: {}
};

function renderStudioStageTabs(activeTabName) {
    const tabsContainer = document.getElementById('studio-top-tabs');
    if (!tabsContainer) return;

    tabsContainer.querySelectorAll('.dynamic-stage-tab').forEach(el => el.remove());

    const addBtn = document.getElementById('btn-add-new-stage');
    const existingStages = [];

    for (let s = 1; s <= 3; s++) {
        if (workingProfile[`stage${s}`] !== null && workingProfile[`stage${s}`] !== undefined) {
            existingStages.push(s);
            const tab = document.createElement('button');
            tab.className = 'b-tab dynamic-stage-tab';
            tab.setAttribute('data-btab', `stage${s}`);
            const iconClass = s === 1 ? 'fa-arrows-left-right' : (s === 2 ? 'fa-shield-halved' : 'fa-bolt');
            tab.innerHTML = `<i class="fa-solid ${iconClass}"></i> STAGE ${s}`;

            tab.addEventListener('click', () => {
                switchStudioTab(`stage${s}`);
            });

            tabsContainer.insertBefore(tab, addBtn);
        }
    }

    if (addBtn) {
        addBtn.style.display = existingStages.length >= 3 ? 'none' : 'flex';
    }

    if (existingStages.length === 0) {
        switchStudioTab('empty-stages');
    } else {
        const target = activeTabName || `stage${existingStages[0]}`;
        switchStudioTab(target);
    }
}

function switchStudioTab(tabId) {
    document.querySelectorAll('#studio-top-tabs .b-tab').forEach(b => {
        b.classList.toggle('active', b.getAttribute('data-btab') === tabId);
    });
    document.querySelectorAll('.b-tab-pane').forEach(p => {
        p.classList.toggle('active', p.id === `pane-${tabId}`);
    });
}

function openBuilderUI(data) {
    currentEditingModel = (data.modelName || "police").toLowerCase();
    builderModelName.textContent = currentEditingModel.toUpperCase();
    vehicleInstalledExtras = data.installedExtras || [];

    if (data.profile) {
        workingProfile = JSON.parse(JSON.stringify(data.profile));
    } else {
        workingProfile = {
            speed: 75,
            sirenBank: "VEHICLES_HORNS_SIREN_1",
            stage1: null,
            stage2: null,
            stage3: null,
            takedown: [],
            alleyLeft: [],
            alleyRight: [],
            labels: {}
        };
    }

    for (let s = 1; s <= 3; s++) {
        if (workingProfile[`stage${s}`]) {
            const stg = workingProfile[`stage${s}`];
            if (!Array.isArray(stg.phaseA)) stg.phaseA = [];
            if (!Array.isArray(stg.phaseB)) stg.phaseB = [];
            if (!Array.isArray(stg.steady)) stg.steady = [];

            if (!stg.envColors) {
                stg.envColors = {
                    pos: s === 1 ? 'rear' : (s === 2 ? 'roof' : 'both'),
                    colorA: s === 1 ? 'amber' : (s === 2 ? 'red' : 'red'),
                    colorB: s === 1 ? 'amber' : (s === 2 ? 'blue' : 'blue')
                };
            }
            if (!stg.speed) {
                stg.speed = (s === 1 ? 180 : (s === 2 ? 120 : (workingProfile.speed || 80)));
            }

            const selPos = document.getElementById(`stg${s}-env-pos`);
            if (selPos) selPos.value = stg.envColors.pos || (s === 1 ? 'rear' : (s === 2 ? 'roof' : 'both'));
            const selA = document.getElementById(`stg${s}-env-color-a`);
            if (selA) selA.value = stg.envColors.colorA || (s === 1 ? 'amber' : 'red');
            const selB = document.getElementById(`stg${s}-env-color-b`);
            if (selB) selB.value = stg.envColors.colorB || (s === 1 ? 'amber' : 'blue');

            const speedSlider = document.getElementById(`stg${s}-speed-slider`);
            const speedVal = document.getElementById(`stg${s}-speed-val`);
            if (speedSlider && speedVal) {
                speedSlider.value = stg.speed;
                speedVal.textContent = `${stg.speed}ms`;
            }
        }
    }



    builderStatusText.textContent = `Vehicle [${currentEditingModel.toUpperCase()}]. Installed Extras: ${vehicleInstalledExtras.join(', ') || 'None'}`;
    renderInspectorGrid();
    renderAllStudioPickers();
    renderStudioStageTabs();

    if (builderContainer) builderContainer.style.display = 'block';
}

function renderAllStudioPickers() {
    if (workingProfile.stage1) {
        if (!workingProfile.stage1.phaseA) workingProfile.stage1.phaseA = [];
        if (!workingProfile.stage1.phaseB) workingProfile.stage1.phaseB = [];
        if (!workingProfile.stage1.steady) workingProfile.stage1.steady = [];
        setupPicker('stg1-phaseA-picker', workingProfile.stage1.phaseA);
        setupPicker('stg1-phaseB-picker', workingProfile.stage1.phaseB);
        setupPicker('stg1-steady-picker', workingProfile.stage1.steady);
    }

    if (workingProfile.stage2) {
        if (!workingProfile.stage2.phaseA) workingProfile.stage2.phaseA = [];
        if (!workingProfile.stage2.phaseB) workingProfile.stage2.phaseB = [];
        if (!workingProfile.stage2.steady) workingProfile.stage2.steady = [];
        setupPicker('stg2-phaseA-picker', workingProfile.stage2.phaseA);
        setupPicker('stg2-phaseB-picker', workingProfile.stage2.phaseB);
        setupPicker('stg2-steady-picker', workingProfile.stage2.steady);
    }

    if (workingProfile.stage3) {
        if (!workingProfile.stage3.phaseA) workingProfile.stage3.phaseA = [];
        if (!workingProfile.stage3.phaseB) workingProfile.stage3.phaseB = [];
        if (!workingProfile.stage3.steady) workingProfile.stage3.steady = [];
        setupPicker('stg3-phaseA-picker', workingProfile.stage3.phaseA);
        setupPicker('stg3-phaseB-picker', workingProfile.stage3.phaseB);
        setupPicker('stg3-steady-picker', workingProfile.stage3.steady);
    }
}

function addNewStage() {
    for (let s = 1; s <= 3; s++) {
        if (!workingProfile[`stage${s}`]) {
            workingProfile[`stage${s}`] = {
                speed: s === 1 ? 180 : (s === 2 ? 120 : 80),
                phaseA: [],
                phaseB: [],
                steady: [],
                envColors: {
                    pos: s === 1 ? 'rear' : (s === 2 ? 'roof' : 'both'),
                    colorA: s === 1 ? 'amber' : (s === 2 ? 'red' : 'red'),
                    colorB: s === 1 ? 'amber' : (s === 2 ? 'blue' : 'blue')
                }
            };
            renderAllStudioPickers();
            renderStudioStageTabs(`stage${s}`);
            builderStatusText.textContent = `Created STAGE ${s}. Add extras to configure lights!`;
            return;
        }
    }
}

function removeStage(stageNum) {
    stageNum = parseInt(stageNum, 10);
    if (workingProfile[`stage${stageNum}`]) {
        workingProfile[`stage${stageNum}`] = null;
        renderStudioStageTabs();
        builderStatusText.textContent = `Removed STAGE ${stageNum}.`;
    }
}

document.getElementById('btn-add-new-stage')?.addEventListener('click', () => addNewStage());
document.getElementById('btn-create-first-stage')?.addEventListener('click', () => addNewStage());

document.querySelectorAll('.stage-del-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        const s = btn.getAttribute('data-delstg');
        removeStage(s);
    });
});

for (let s = 1; s <= 3; s++) {
    const slider = document.getElementById(`stg${s}-speed-slider`);
    const valBadge = document.getElementById(`stg${s}-speed-val`);
    slider?.addEventListener('input', (e) => {
        const spd = parseInt(e.target.value, 10);
        if (valBadge) valBadge.textContent = `${spd}ms`;
        if (workingProfile[`stage${s}`]) {
            workingProfile[`stage${s}`].speed = spd;
            if (s === 3) workingProfile.speed = spd;
        }
    });
}

for (let s = 1; s <= 3; s++) {
    document.getElementById(`stg${s}-env-pos`)?.addEventListener('change', (e) => {
        if (!workingProfile[`stage${s}`]) return;
        if (!workingProfile[`stage${s}`].envColors) workingProfile[`stage${s}`].envColors = {};
        workingProfile[`stage${s}`].envColors.pos = e.target.value;
    });
    document.getElementById(`stg${s}-env-color-a`)?.addEventListener('change', (e) => {
        if (!workingProfile[`stage${s}`]) return;
        if (!workingProfile[`stage${s}`].envColors) workingProfile[`stage${s}`].envColors = {};
        workingProfile[`stage${s}`].envColors.colorA = e.target.value;
    });
    document.getElementById(`stg${s}-env-color-b`)?.addEventListener('change', (e) => {
        if (!workingProfile[`stage${s}`]) return;
        if (!workingProfile[`stage${s}`].envColors) workingProfile[`stage${s}`].envColors = {};
        workingProfile[`stage${s}`].envColors.colorB = e.target.value;
    });
}

function closeBuilderUI() {
    if (builderContainer) builderContainer.style.display = 'none';
    postNUI('builderStopTest');
    postNUI('closeBuilder');
}



function renderInspectorGrid() {
    const grid = document.getElementById('builder-inspector-grid');
    if (!grid) return;
    grid.innerHTML = '';

    for (let i = 1; i <= 12; i++) {
        const isInstalled = vehicleInstalledExtras.length === 0 || vehicleInstalledExtras.includes(i);
        const btn = document.createElement('button');
        btn.className = `insp-btn ${!isInstalled ? 'unavailable' : ''}`;
        btn.innerHTML = `<i class="fa-solid fa-lightbulb"></i> E${i}`;
        btn.title = `Extra ${i} (${isInstalled ? 'Installed' : 'Unavailable'})`;

        if (isInstalled) {
            btn.addEventListener('click', () => {
                const isActive = (activeInspectExtra === i);
                if (isActive) {
                    activeInspectExtra = null;
                    btn.classList.remove('active-inspect');
                    postNUI('builderInspectExtra', { extraId: 0 });
                } else {
                    activeInspectExtra = i;
                    grid.querySelectorAll('.insp-btn').forEach(b => b.classList.remove('active-inspect'));
                    btn.classList.add('active-inspect');
                    postNUI('builderInspectExtra', { extraId: i });
                }
            });
        }
        grid.appendChild(btn);
    }
}

let activeTestingStage = null;

function setupPicker(containerId, selectedArray, isSingle = false) {
    const container = document.getElementById(containerId);
    if (!container) return;
    container.innerHTML = '';

    for (let i = 1; i <= 12; i++) {
        const isInstalled = vehicleInstalledExtras.length === 0 || vehicleInstalledExtras.includes(i);
        const isSelected = Array.isArray(selectedArray) && selectedArray.includes(i);

        const btn = document.createElement('button');
        btn.className = `b-extra-pill ${isSelected ? 'selected' : ''} ${!isInstalled ? 'unavailable' : ''}`;
        btn.textContent = `E${i}`;
        btn.title = `Extra ${i} (${isInstalled ? 'Installed' : 'Not on vehicle'})`;

        btn.addEventListener('click', () => {
            const idx = selectedArray.indexOf(i);
            if (idx > -1) {
                selectedArray.splice(idx, 1);
                btn.classList.remove('selected');
            } else {
                if (isSingle) selectedArray.length = 0;
                selectedArray.push(i);
                if (isSingle) {
                    container.querySelectorAll('.b-extra-pill').forEach(b => b.classList.remove('selected'));
                }
                btn.classList.add('selected');
            }

            if (activeTestingStage) {
                postNUI('builderTestStage', { stage: activeTestingStage, profile: workingProfile });
            }
        });

        container.appendChild(btn);
    }
}

document.getElementById('cam-preset-front')?.addEventListener('click', () => {
    postNUI('rotateCamera', { preset: 'front' });
});
document.getElementById('cam-preset-back')?.addEventListener('click', () => {
    postNUI('rotateCamera', { preset: 'back' });
});
document.getElementById('cam-preset-left')?.addEventListener('click', () => {
    postNUI('rotateCamera', { preset: 'left' });
});
document.getElementById('cam-preset-right')?.addEventListener('click', () => {
    postNUI('rotateCamera', { preset: 'right' });
});
document.getElementById('cam-preset-top')?.addEventListener('click', () => {
    postNUI('rotateCamera', { preset: 'top' });
});

document.getElementById('cam-rot-ccw')?.addEventListener('click', () => {
    postNUI('rotateCamera', { deltaYaw: -45 });
});
document.getElementById('cam-rot-cw')?.addEventListener('click', () => {
    postNUI('rotateCamera', { deltaYaw: 45 });
});

document.querySelectorAll('.b-top-tabs .b-tab:not(.add-stage-tab-btn)').forEach(tabBtn => {
    tabBtn.addEventListener('click', () => {
        const target = tabBtn.getAttribute('data-btab');
        if (target) {
            switchStudioTab(target);
        }
    });
});

stg3SpeedSlider?.addEventListener('input', (e) => {
    const val = parseInt(e.target.value, 10);
    workingProfile.speed = val;
    stg3SpeedVal.textContent = `${val}ms`;
    if (activeTestingStage) {
        postNUI('builderTestStage', { stage: activeTestingStage, profile: workingProfile });
    }
});

document.getElementById('btn-test-stg1')?.addEventListener('click', () => {
    activeTestingStage = 1;
    updateTestBtnStyles('btn-test-stg1');
    postNUI('builderTestStage', { stage: 1, profile: workingProfile });
    builderStatusText.textContent = "Live Testing STAGE 1 on vehicle...";
});

document.getElementById('btn-test-stg2')?.addEventListener('click', () => {
    activeTestingStage = 2;
    updateTestBtnStyles('btn-test-stg2');
    postNUI('builderTestStage', { stage: 2, profile: workingProfile });
    builderStatusText.textContent = "Live Testing STAGE 2 on vehicle...";
});

document.getElementById('btn-test-stg3')?.addEventListener('click', () => {
    activeTestingStage = 3;
    updateTestBtnStyles('btn-test-stg3');
    postNUI('builderTestStage', { stage: 3, profile: workingProfile });
    builderStatusText.textContent = "Live Testing CODE 3 on vehicle...";
});

document.getElementById('btn-test-stop')?.addEventListener('click', () => {
    activeTestingStage = null;
    activeInspectExtra = null;
    document.querySelectorAll('.insp-btn').forEach(b => b.classList.remove('active-inspect'));
    updateTestBtnStyles(null);
    postNUI('builderStopTest');
    builderStatusText.textContent = "Preview test stopped.";
});

function updateTestBtnStyles(activeBtnId) {
    ['btn-test-stg1', 'btn-test-stg2', 'btn-test-stg3'].forEach(id => {
        const el = document.getElementById(id);
        if (el) el.classList.toggle('active-testing', id === activeBtnId);
    });
}

document.getElementById('builder-btn-save')?.addEventListener('click', () => {
    postNUI('builderSaveProfile', {
        modelName: currentEditingModel,
        profile: workingProfile
    });
    builderStatusText.textContent = `✔ Profile successfully saved for [${currentEditingModel.toUpperCase()}]!`;
    setTimeout(() => {
        closeBuilderUI();
    }, 900);
});

document.getElementById('builder-btn-reset')?.addEventListener('click', () => {
    postNUI('builderResetProfile', { modelName: currentEditingModel });
    builderStatusText.textContent = `Reset to default template for [${currentEditingModel.toUpperCase()}].`;
    setTimeout(() => {
        closeBuilderUI();
    }, 700);
});

document.getElementById('builder-btn-close')?.addEventListener('click', closeBuilderUI);
