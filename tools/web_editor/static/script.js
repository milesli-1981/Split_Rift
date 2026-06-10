// --- Core Elements ---
const editorCanvas = document.getElementById('editorCanvas');
const edCtx = editorCanvas.getContext('2d');
const composerCanvas = document.getElementById('composerCanvas');
const compCtx = composerCanvas.getContext('2d');
const previewCanvas = document.getElementById('previewCanvas');
const prevCtx = previewCanvas.getContext('2d');

// Editor Toolbar
const fileInput = document.getElementById('fileInput');
const toleranceInput = document.getElementById('tolerance');
const toleranceVal = document.getElementById('toleranceVal');
const eraserBtn = document.getElementById('eraserBtn');
const selectBtn = document.getElementById('selectBtn');
const undoBtn = document.getElementById('undoBtn');
const brushSizeInput = document.getElementById('brushSize');
const sliceBtn = document.getElementById('sliceBtn');
const collectionList = document.getElementById('collectionList');
const clearCollectionBtn = document.getElementById('clearCollectionBtn');
const downloadEditorBtn = document.getElementById('downloadEditorBtn');
const applyChangesBtn = document.getElementById('applyChangesBtn');

// Composer Toolbar
const gridToggle = document.getElementById('gridToggle');
const gridColsSelect = document.getElementById('gridColsSelect');
const autoAlignBtn = document.getElementById('autoAlignBtn');
const deleteFrameBtn = document.getElementById('deleteFrameBtn');
const downloadSheetBtn = document.getElementById('downloadSheetBtn');
const fpsSlider = document.getElementById('fpsSlider');
const fpsVal = document.getElementById('fpsVal');
const frameScaleSlider = document.getElementById('frameScaleSlider');
const frameScaleVal = document.getElementById('frameScaleVal');
const framePropsPanel = document.getElementById('framePropsPanel');
const noFrameSelectedHint = document.getElementById('noFrameSelectedHint');
const composerFrameList = document.getElementById('composerFrameList');

// Video elements
const videoFileInput = document.getElementById('videoFileInput');
const videoPreview = document.getElementById('videoPreview');
const videoStart = document.getElementById('videoStart');
const videoEnd = document.getElementById('videoEnd');
const videoFps = document.getElementById('videoFps');
const extractVideoFramesBtn = document.getElementById('extractVideoFramesBtn');
const videoTimeRangeDisplay = document.getElementById('videoTimeRangeDisplay');

// --- Global State ---
let baseImage = new Image(); // The original uploaded/sliced image (constant)
let undoStack = [];
const MAX_UNDO = 20;

// Layers
const eraserCanvas = document.createElement('canvas'); // Persistent manual erasures
const erCtx = eraserCanvas.getContext('2d');
const displayCanvas = document.createElement('canvas'); // Temp buffer for clean + eraser
const dsCtx = displayCanvas.getContext('2d');

let frames = []; // { canvas, x, y, w, h, scale, anchorX, anchorY }
let selectedFrameIndex = -1;

// Editor interaction state
let isDrawing = false;
let currentTool = 'none';
let selectionStart = null;
let selectionRect = null;

// Composer interaction state
let isDraggingFrame = false;
let dragOffset = { x: 0, y: 0 };
let currentPreviewFrame = 0;
let lastFrameTime = 0;

// --- Tab Logic ---
document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
        document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
        btn.classList.add('active');
        document.getElementById(btn.dataset.tab + 'View').classList.add('active');
        if (btn.dataset.tab === 'composer') {
            updateComposerFrameListUI();
            renderComposer();
        }
    });
});

// --- Editor Logic ---

function saveUndoState() {
    // Save current state of components
    undoStack.push({
        base: baseImage.src,
        eraser: eraserCanvas.toDataURL(),
        tolerance: toleranceInput.value
    });
    if (undoStack.length > MAX_UNDO) undoStack.shift();
}

function undo() {
    if (undoStack.length === 0) return;
    const state = undoStack.pop();
    
    toleranceInput.value = state.tolerance;
    toleranceVal.textContent = state.tolerance;
    
    const loadBase = new Promise(resolve => {
        const img = new Image();
        img.onload = () => { baseImage = img; resolve(); };
        img.src = state.base;
    });
    
    const loadEraser = new Promise(resolve => {
        const img = new Image();
        img.onload = () => {
            erCtx.clearRect(0, 0, eraserCanvas.width, eraserCanvas.height);
            erCtx.drawImage(img, 0, 0);
            resolve();
        };
        img.src = state.eraser;
    });
    
    Promise.all([loadBase, loadEraser]).then(() => renderAll());
}

undoBtn.addEventListener('click', undo);
window.addEventListener('keydown', (e) => {
    if (e.ctrlKey && e.key === 'z') { e.preventDefault(); undo(); }
});

fileInput.addEventListener('change', (e) => {
    const file = e.target.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (event) => loadToEditor(event.target.result);
    reader.readAsDataURL(file);
});

function loadToEditor(url) {
    baseImage.onload = () => {
        const w = baseImage.width;
        const h = baseImage.height;
        
        editorCanvas.width = w;
        editorCanvas.height = h;
        eraserCanvas.width = w;
        eraserCanvas.height = h;
        displayCanvas.width = w;
        displayCanvas.height = h;
        
        erCtx.clearRect(0, 0, w, h);
        
        undoStack = [];
        toleranceInput.value = 0;
        toleranceVal.textContent = 0;
        
        renderAll();
    };
    baseImage.src = url;
}

function renderAll() {
    const w = editorCanvas.width;
    const h = editorCanvas.height;
    
    // 1. Calculate Cleaned Version in displayCanvas buffer
    dsCtx.clearRect(0, 0, w, h);
    dsCtx.drawImage(baseImage, 0, 0);
    
    const tolerance = parseInt(toleranceInput.value);
    toleranceVal.textContent = tolerance;
    
    if (tolerance > 0) {
        const imageData = dsCtx.getImageData(0, 0, w, h);
        const data = imageData.data;
        
        // Sample from corners of baseImage (unmodified)
        const samples = [
            {r: data[0], g: data[1], b: data[2]},
            {r: data[(w-1)*4], g: data[(w-1)*4+1], b: data[(w-1)*4+2]},
            {r: data[(data.length-w*4)], g: data[(data.length-w*4)+1], b: data[(data.length-w*4)+2]},
            {r: data[data.length-4], g: data[data.length-3], b: data[data.length-2]}
        ];
        const bgColor = {
            r: samples.reduce((a, b) => a + b.r, 0) / 4,
            g: samples.reduce((a, b) => a + b.g, 0) / 4,
            b: samples.reduce((a, b) => a + b.b, 0) / 4
        };
        
        for (let i = 0; i < data.length; i += 4) {
            if (data[i+3] === 0) continue;
            const diff = Math.sqrt(Math.pow(data[i]-bgColor.r, 2) + Math.pow(data[i+1]-bgColor.g, 2) + Math.pow(data[i+2]-bgColor.b, 2));
            if (diff < tolerance) data[i+3] = 0;
        }
        dsCtx.putImageData(imageData, 0, 0);
    }
    
    // 2. Apply Manual Eraser layer
    dsCtx.globalCompositeOperation = 'destination-out';
    dsCtx.drawImage(eraserCanvas, 0, 0);
    dsCtx.globalCompositeOperation = 'source-over';
    
    // 3. Draw to final screen
    edCtx.clearRect(0, 0, w, h);
    edCtx.drawImage(displayCanvas, 0, 0);
    
    // 4. Draw selection UI
    if (selectionRect) {
        edCtx.strokeStyle = '#0078d4';
        edCtx.lineWidth = 2;
        edCtx.setLineDash([5, 5]);
        edCtx.strokeRect(selectionRect.x, selectionRect.y, selectionRect.w, selectionRect.h);
        edCtx.setLineDash([]);
        edCtx.fillStyle = 'rgba(0, 120, 212, 0.15)';
        edCtx.fillRect(selectionRect.x, selectionRect.y, selectionRect.w, selectionRect.h);
    }
}

// Real-time Auto Clean
toleranceInput.addEventListener('input', renderAll);

// When slider release, save undo state
toleranceInput.addEventListener('change', saveUndoState);

// Tool Selection
eraserBtn.onclick = () => { currentTool = currentTool === 'eraser' ? 'none' : 'eraser'; updateToolUI(); };
selectBtn.onclick = () => { currentTool = currentTool === 'select' ? 'none' : 'select'; updateToolUI(); };

function updateToolUI() {
    eraserBtn.classList.toggle('active', currentTool === 'eraser');
    selectBtn.classList.toggle('active', currentTool === 'select');
    if (currentTool !== 'select') { 
        selectionRect = null; 
        sliceBtn.disabled = true; 
    }
    renderAll();
}

editorCanvas.addEventListener('mousedown', (e) => {
    if (currentTool === 'eraser') {
        saveUndoState();
        isDrawing = true;
        drawEraser(e);
    } else if (currentTool === 'select') {
        const rect = editorCanvas.getBoundingClientRect();
        selectionStart = {
            x: (e.clientX - rect.left) * (editorCanvas.width / rect.width),
            y: (e.clientY - rect.top) * (editorCanvas.height / rect.height)
        };
        isDrawing = true;
    }
});

editorCanvas.addEventListener('mousemove', (e) => {
    if (!isDrawing) return;
    const rect = editorCanvas.getBoundingClientRect();
    const curX = (e.clientX - rect.left) * (editorCanvas.width / rect.width);
    const curY = (e.clientY - rect.top) * (editorCanvas.height / rect.height);

    if (currentTool === 'eraser') {
        drawEraser(e);
    } else if (currentTool === 'select' && selectionStart) {
        selectionRect = {
            x: Math.min(selectionStart.x, curX),
            y: Math.min(selectionStart.y, curY),
            w: Math.abs(curX - selectionStart.x),
            h: Math.abs(curY - selectionStart.y)
        };
        renderAll();
    }
});

window.addEventListener('mouseup', () => {
    isDrawing = false;
    if (currentTool === 'select' && selectionRect && selectionRect.w > 5) sliceBtn.disabled = false;
    selectionStart = null;
});

function drawEraser(e) {
    const rect = editorCanvas.getBoundingClientRect();
    const x = (e.clientX - rect.left) * (editorCanvas.width / rect.width);
    const y = (e.clientY - rect.top) * (editorCanvas.height / rect.height);
    
    // Draw onto the persistent eraser layer
    erCtx.fillStyle = 'black'; // Color doesn't matter for destination-out
    erCtx.beginPath();
    erCtx.arc(x, y, brushSizeInput.value / 2, 0, Math.PI * 2);
    erCtx.fill();
    
    renderAll();
}

sliceBtn.onclick = () => {
    if (!selectionRect) return;
    
    // Create the sliced image from the CURRENT displayCanvas (which has clean + eraser)
    const frameCanvas = document.createElement('canvas');
    frameCanvas.width = selectionRect.w;
    frameCanvas.height = selectionRect.h;
    frameCanvas.getContext('2d').drawImage(displayCanvas, selectionRect.x, selectionRect.y, selectionRect.w, selectionRect.h, 0, 0, selectionRect.w, selectionRect.h);
    
    // Push to Collection
    frames.push({
        canvas: frameCanvas,
        x: (frames.length % 4) * 200 + 50,
        y: Math.floor(frames.length / 4) * 200 + 50,
        w: selectionRect.w,
        h: selectionRect.h,
        scale: 1.0,
        anchorX: selectionRect.w / 2,
        anchorY: selectionRect.h / 2,
        visible: true // Added visibility property
    });
    
    // Keep the original canvas as is, just clear selection
    updateCollectionUI();
    selectionRect = null;
    sliceBtn.disabled = true;
    renderAll(); // Redraw to remove the selection box UI
    alert('已切片并加入 Collection！您可以继续在原图上切片。');
};

function updateCollectionUI() {
    collectionList.innerHTML = '';
    frames.forEach((f, i) => {
        const li = document.createElement('li');
        li.className = 'frame-item';
        if (i === selectedFrameIndex && document.querySelector('.tab-btn.active').dataset.tab === 'editor') li.classList.add('active');

        const imgHtml = `<img src="${f.canvas.toDataURL()}">`;
        const infoHtml = `<div class="info">帧 ${i+1}<br>${f.w}x${f.h}</div>`;
        
        li.innerHTML = imgHtml + infoHtml;
        
        li.onclick = () => {
            loadToEditor(f.canvas.toDataURL());
            selectedFrameIndex = i;
            updateCollectionUI();
            document.querySelector('.tab-btn[data-tab="editor"]').click();
        };
        collectionList.appendChild(li);
    });
}

function updateComposerFrameListUI() {
    composerFrameList.innerHTML = '';
    frames.forEach((f, i) => {
        const li = document.createElement('li');
        li.className = 'frame-item';
        if (i === selectedFrameIndex && document.querySelector('.tab-btn.active').dataset.tab === 'composer') li.classList.add('active');
        if (!f.visible) li.style.opacity = '0.5';

        const imgHtml = `<img src="${f.canvas.toDataURL()}">`;
        const infoHtml = `<div class="info">帧 ${i+1}</div>`;
        const eyeHtml = `<button class="eye-btn" title="预览显示/隐藏">${f.visible ? '👁️' : '🚫'}</button>`;
        
        li.innerHTML = imgHtml + infoHtml + eyeHtml;
        
        li.querySelector('.eye-btn').onclick = (e) => {
            e.stopPropagation();
            f.visible = !f.visible;
            updateComposerFrameListUI();
            renderComposer();
        };

        li.onclick = () => {
            selectedFrameIndex = i;
            updateComposerFrameListUI();
            renderComposer();
        };
        composerFrameList.appendChild(li);
    });
}

clearCollectionBtn.onclick = () => { frames = []; selectedFrameIndex = -1; updateCollectionUI(); if(document.querySelector('.tab-btn[data-tab="composer"]').classList.contains('active')) renderComposer(); };
downloadEditorBtn.onclick = () => { const a = document.createElement('a'); a.download = 'editor_export.png'; a.href = editorCanvas.toDataURL(); a.click(); };

applyChangesBtn.onclick = () => {
    // Solidify the current view (Clean + Eraser) as the new baseImage
    saveUndoState();
    const dataURL = editorCanvas.toDataURL('image/png');
    const tempImg = new Image();
    tempImg.onload = () => {
        baseImage = tempImg;
        erCtx.clearRect(0, 0, eraserCanvas.width, eraserCanvas.height);
        toleranceInput.value = 0;
        toleranceVal.textContent = 0;
        renderAll();
        
        // If this frame was from Collection, update it
        if (selectedFrameIndex !== -1) {
            const frameCanvas = document.createElement('canvas');
            frameCanvas.width = baseImage.width;
            frameCanvas.height = baseImage.height;
            frameCanvas.getContext('2d').drawImage(baseImage, 0, 0);
            frames[selectedFrameIndex].canvas = frameCanvas;
            updateCollectionUI();
        }
        alert('修改已应用到基准图！');
    };
    tempImg.src = dataURL;
};

// --- Video Logic ---
videoFileInput.addEventListener('change', (e) => {
    const file = e.target.files[0];
    if (!file) return;
    const url = URL.createObjectURL(file);
    videoPreview.src = url;
    videoPreview.onloadedmetadata = () => {
        videoEnd.value = videoPreview.duration.toFixed(1);
        videoEnd.max = videoPreview.duration;
        videoStart.max = videoPreview.duration;
        updateVideoTimeDisplay();
        extractVideoFramesBtn.disabled = false;
    };
});

function updateVideoTimeDisplay() {
    videoTimeRangeDisplay.textContent = `${parseFloat(videoStart.value).toFixed(1)}s - ${parseFloat(videoEnd.value).toFixed(1)}s`;
}

videoStart.oninput = updateVideoTimeDisplay;
videoEnd.oninput = updateVideoTimeDisplay;

extractVideoFramesBtn.onclick = async () => {
    const file = videoFileInput.files[0];
    if (!file) return;

    extractVideoFramesBtn.disabled = true;
    extractVideoFramesBtn.textContent = '处理中...';

    const formData = new FormData();
    formData.append('video', file);
    formData.append('start', videoStart.value);
    formData.append('end', videoEnd.value);
    formData.append('fps', videoFps.value);

    try {
        const response = await fetch('/process_video', {
            method: 'POST',
            body: formData
        });
        const data = await response.json();

        if (data.success) {
            for (const frameData of data.frames) {
                const tempImg = new Image();
                await new Promise(resolve => {
                    tempImg.onload = () => {
                        const frameCanvas = document.createElement('canvas');
                        frameCanvas.width = tempImg.width;
                        frameCanvas.height = tempImg.height;
                        frameCanvas.getContext('2d').drawImage(tempImg, 0, 0);
                        
        frames.push({
            canvas: frameCanvas,
            x: (frames.length % 4) * 200 + 50,
            y: Math.floor(frames.length / 4) * 200 + 50,
            w: tempImg.width,
            h: tempImg.height,
            scale: 1.0,
            anchorX: tempImg.width / 2,
            anchorY: tempImg.height / 2,
            visible: true // Added visibility property
        });
                        resolve();
                    };
                    tempImg.src = frameData;
                });
            }
            updateCollectionUI();
            alert(`成功提取 ${data.frames.length} 帧并加入 Collection！`);
        } else {
            alert('处理失败: ' + data.error);
        }
    } catch (e) {
        alert('请求出错: ' + e);
    } finally {
        extractVideoFramesBtn.disabled = false;
        extractVideoFramesBtn.textContent = '提取并加入 Collection';
    }
};

// --- Composer Logic ---

function renderComposer(forExport = false) {
    compCtx.clearRect(0, 0, 1024, 1024);
    if (gridToggle.checked && !forExport) {
        compCtx.strokeStyle = '#333';
        compCtx.lineWidth = 1;
        for (let i = 0; i <= 1024; i += 64) {
            compCtx.beginPath(); compCtx.moveTo(i, 0); compCtx.lineTo(i, 1024); compCtx.stroke();
            compCtx.beginPath(); compCtx.moveTo(0, i); compCtx.lineTo(1024, i); compCtx.stroke();
        }
    }

    frames.forEach((f, i) => {
        const fw = f.w * f.scale;
        const fh = f.h * f.scale;
        
        compCtx.save();
        if (!f.visible) compCtx.globalAlpha = 0.2; // Dim hidden frames
        compCtx.drawImage(f.canvas, f.x, f.y, fw, fh);
        
        // Draw Anchor (ONLY if not exporting)
        if (!forExport) {
            compCtx.fillStyle = 'red';
            compCtx.beginPath();
            compCtx.arc(f.x + f.anchorX * f.scale, f.y + f.anchorY * f.scale, 4, 0, Math.PI * 2);
            compCtx.fill();
        }
        compCtx.restore();

        if (i === selectedFrameIndex && !forExport) {
            compCtx.strokeStyle = '#0078d4';
            compCtx.lineWidth = 2;
            compCtx.strokeRect(f.x, f.y, fw, fh);
        }
    });

    if (selectedFrameIndex !== -1) {
        framePropsPanel.style.display = 'block';
        noFrameSelectedHint.style.display = 'none';
        const f = frames[selectedFrameIndex];
        frameScaleSlider.value = f.scale;
        frameScaleVal.textContent = f.scale.toFixed(2);
        deleteFrameBtn.disabled = false;
    } else {
        framePropsPanel.style.display = 'none';
        noFrameSelectedHint.style.display = 'block';
        deleteFrameBtn.disabled = true;
    }
}

composerCanvas.addEventListener('mousedown', (e) => {
    const rect = composerCanvas.getBoundingClientRect();
    const mx = (e.clientX - rect.left) * (1024 / rect.width);
    const my = (e.clientY - rect.top) * (1024 / rect.height);
    
    // Check if clicked inside a frame
    let found = -1;
    for (let i = frames.length - 1; i >= 0; i--) {
        const f = frames[i];
        const fw = f.w * f.scale;
        const fh = f.h * f.scale;
        if (mx >= f.x && mx <= f.x + fw && my >= f.y && my <= f.y + fh) {
            found = i;
            // Set anchor if clicking inside selected frame
            if (i === selectedFrameIndex) {
                f.anchorX = (mx - f.x) / f.scale;
                f.anchorY = (my - f.y) / f.scale;
            }
            break;
        }
    }
    
    selectedFrameIndex = found;
    if (selectedFrameIndex !== -1) {
        isDraggingFrame = true;
        dragOffset = { x: mx - frames[selectedFrameIndex].x, y: my - frames[selectedFrameIndex].y };
    }
    renderComposer();
    updateComposerFrameListUI();
});

window.addEventListener('mousemove', (e) => {
    if (!isDraggingFrame || selectedFrameIndex === -1) return;
    const rect = composerCanvas.getBoundingClientRect();
    const mx = (e.clientX - rect.left) * (1024 / rect.width);
    const my = (e.clientY - rect.top) * (1024 / rect.height);
    const f = frames[selectedFrameIndex];
    f.x = mx - dragOffset.x;
    f.y = my - dragOffset.y;
    if (gridToggle.checked) {
        f.x = Math.round(f.x / 16) * 16;
        f.y = Math.round(f.y / 16) * 16;
    }
    renderComposer();
});

window.addEventListener('mouseup', () => isDraggingFrame = false);

autoAlignBtn.onclick = () => {
    const cols = parseInt(gridColsSelect.value);
    const step = 1024 / cols;
    frames.forEach((f, i) => {
        const col = i % cols;
        const row = Math.floor(i / cols);
        const centerX = col * step + step / 2;
        const centerY = row * step + step / 2;
        f.x = centerX - f.anchorX * f.scale;
        f.y = centerY - f.anchorY * f.scale;
    });
    renderComposer();
};

deleteFrameBtn.onclick = () => { if (selectedFrameIndex !== -1) { frames.splice(selectedFrameIndex, 1); selectedFrameIndex = -1; renderComposer(); updateComposerFrameListUI(); updateCollectionUI(); } };
frameScaleSlider.oninput = () => { 
    if (selectedFrameIndex !== -1) { 
        frames[selectedFrameIndex].scale = parseFloat(frameScaleSlider.value); 
        frameScaleVal.textContent = frames[selectedFrameIndex].scale.toFixed(2); 
        renderComposer(); 
    } 
};
gridToggle.onchange = renderComposer;

// Preview Animation
function animate(time) {
    const interval = 1000 / parseInt(fpsSlider.value);
    const visibleFrames = frames.filter(f => f.visible);
    
    if (time - lastFrameTime > interval && visibleFrames.length > 0) {
        lastFrameTime = time;
        currentPreviewFrame = (currentPreviewFrame + 1) % visibleFrames.length;
        const f = visibleFrames[currentPreviewFrame];
        prevCtx.clearRect(0, 0, 256, 256);
        
        // --- FIX: Determine a global fitting scale based on ALL visible frames ---
        let maxDim = 0;
        visibleFrames.forEach(vf => {
            maxDim = Math.max(maxDim, vf.w * vf.scale, vf.h * vf.scale);
        });
        // We want the largest frame to fit in a 200px box, while others stay relative
        const globalFit = maxDim > 200 ? 200 / maxDim : 1.0;
        const finalScale = globalFit * f.scale;
        
        prevCtx.save();
        prevCtx.translate(128, 128); // Center of preview
        prevCtx.scale(finalScale, finalScale);
        prevCtx.drawImage(f.canvas, -f.anchorX, -f.anchorY);
        prevCtx.restore();
        
        // Crosshair
        prevCtx.strokeStyle = 'rgba(255,0,0,0.2)';
        prevCtx.beginPath(); prevCtx.moveTo(128, 118); prevCtx.lineTo(128, 138); prevCtx.stroke();
        prevCtx.beginPath(); prevCtx.moveTo(118, 128); prevCtx.lineTo(138, 128); prevCtx.stroke();
    } else if (visibleFrames.length === 0) {
        prevCtx.clearRect(0, 0, 256, 256);
    }
    requestAnimationFrame(animate);
}
requestAnimationFrame(animate);
fpsSlider.oninput = () => fpsVal.textContent = fpsSlider.value;

downloadSheetBtn.onclick = () => {
    // 1. Render the "Clean" version for export (this will hide grid, anchors, and selection)
    renderComposer(true);
    
    // 2. Download
    const link = document.createElement('a');
    link.download = 'spritesheet_master.png';
    link.href = composerCanvas.toDataURL();
    link.click();
    
    // 3. Restore UI state
    renderComposer(false);
};
