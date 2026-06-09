const sourceCanvas = document.getElementById('sourceCanvas');
const mainCanvas = document.getElementById('mainCanvas');
const previewCanvas = document.getElementById('previewCanvas');
const sourceCtx = sourceCanvas.getContext('2d');
const mainCtx = mainCanvas.getContext('2d');
const previewCtx = previewCanvas.getContext('2d');

const uploadInput = document.getElementById('uploadInput');
const downloadBtn = document.getElementById('downloadBtn');
const gridToggle = document.getElementById('gridToggle');
const framesUl = document.getElementById('framesUl');
const miniFrameList = document.getElementById('miniFrameList');
const fpsSlider = document.getElementById('fpsSlider');
const fpsVal = document.getElementById('fpsVal');
const clearCacheBtn = document.getElementById('clearCacheBtn');
const frameControlPanel = document.getElementById('frameControlPanel');
const frameScaleSlider = document.getElementById('frameScaleSlider');
const frameScaleVal = document.getElementById('frameScaleVal');
const deleteFrameBtn = document.getElementById('deleteFrameBtn');
const autoAlignBtn = document.getElementById('autoAlignBtn');
const gridColsSelect = document.getElementById('gridColsSelect');
const gridRowsSelect = document.getElementById('gridRowsSelect');
const cleanerTolerance = document.getElementById('cleanerTolerance');
const toleranceVal = document.getElementById('toleranceVal');
const enableCleaner = document.getElementById('enableCleaner');

const tabBtns = document.querySelectorAll('.tab-btn');
const tabContents = document.querySelectorAll('.tab-content');

let sourceImage = null;
let frames = []; // { canvas, x, y, w, h, scale, anchorX, anchorY }
let selectedFrameIndex = -1;
let isSelecting = false;
let selectionStart = { x: 0, y: 0 };
let selectionEnd = { x: 0, y: 0 };

let isDragging = false;
let isResizing = false;
let dragOffset = { x: 0, y: 0 };
const HANDLE_SIZE = 12;

let rawSourceImage = null; // Original uploaded image
let processedSourceImage = null; // Cleaned version for preview/selection

// Animation state
let currentPreviewFrame = 0;
let lastFrameTime = 0;

// --- Tab Logic ---
tabBtns.forEach(btn => {
    btn.addEventListener('click', () => {
        const tabId = btn.dataset.tab;
        tabBtns.forEach(b => b.classList.remove('active'));
        tabContents.forEach(c => c.classList.remove('active'));
        btn.classList.add('active');
        document.getElementById(tabId + 'View').classList.add('active');
        
        if (tabId === 'composition') {
            renderMain();
        }
    });
});

// --- Source Canvas Logic ---
uploadInput.addEventListener('change', (e) => {
    const file = e.target.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (event) => {
        rawSourceImage = new Image();
        rawSourceImage.onload = () => {
            sourceCanvas.width = rawSourceImage.width;
            sourceCanvas.height = rawSourceImage.height;
            updateProcessedImage();
        };
        rawSourceImage.src = event.target.result;
    };
    reader.readAsDataURL(file);
});

function updateProcessedImage() {
    if (!rawSourceImage) return;
    
    if (!enableCleaner.checked) {
        processedSourceImage = rawSourceImage;
        renderSource();
        return;
    }

    const tolerance = parseInt(cleanerTolerance.value);
    
    // Create a temporary canvas for processing
    const tempCanvas = document.createElement('canvas');
    tempCanvas.width = rawSourceImage.width;
    tempCanvas.height = rawSourceImage.height;
    const tCtx = tempCanvas.getContext('2d');
    tCtx.drawImage(rawSourceImage, 0, 0);
    
    const imageData = tCtx.getImageData(0, 0, tempCanvas.width, tempCanvas.height);
    const data = imageData.data;
    const w = tempCanvas.width;
    const h = tempCanvas.height;

    // 1. Sample background color from corners
    const samples = [
        getPixel(data, 0, 0, w),
        getPixel(data, w - 1, 0, w),
        getPixel(data, 0, h - 1, w),
        getPixel(data, w - 1, h - 1, w)
    ];
    const bgColor = {
        r: samples.reduce((a, b) => a + b.r, 0) / 4,
        g: samples.reduce((a, b) => a + b.g, 0) / 4,
        b: samples.reduce((a, b) => a + b.b, 0) / 4
    };

    // 2. Flood Fill from all 4 corners to find EXTERNAL background
    const mask = new Uint8Array(w * h); // 0: unknown, 1: external background
    const stack = [[0, 0], [w - 1, 0], [0, h - 1], [w - 1, h - 1]];
    
    while (stack.length > 0) {
        const [x, y] = stack.pop();
        const idx = y * w + x;
        if (mask[idx]) continue;
        
        const pixel = getPixel(data, x, y, w);
        const diff = Math.sqrt(
            Math.pow(pixel.r - bgColor.r, 2) + 
            Math.pow(pixel.g - bgColor.g, 2) + 
            Math.pow(pixel.b - bgColor.b, 2)
        );
        
        if (diff < tolerance * 1.5) {
            mask[idx] = 1;
            if (x > 0) stack.push([x - 1, y]);
            if (x < w - 1) stack.push([x + 1, y]);
            if (y > 0) stack.push([x, y - 1]);
            if (y < h - 1) stack.push([x, y + 1]);
        }
    }

    // 3. Apply mask and soften edges
    for (let i = 0; i < w * h; i++) {
        if (mask[i]) {
            data[i * 4 + 3] = 0; // Fully transparent
        } else {
            // Check distance for edge softening
            const r = data[i * 4];
            const g = data[i * 4 + 1];
            const b = data[i * 4 + 2];
            const diff = Math.sqrt(
                Math.pow(r - bgColor.r, 2) + 
                Math.pow(g - bgColor.g, 2) + 
                Math.pow(b - bgColor.b, 2)
            );
            
            // If near background color, slightly soften
            if (diff < tolerance) {
                const alpha = (diff / tolerance) * 255;
                data[i * 4 + 3] = Math.min(data[i * 4 + 3], alpha);
            }
        }
    }

    tCtx.putImageData(imageData, 0, 0);
    processedSourceImage = new Image();
    processedSourceImage.onload = renderSource;
    processedSourceImage.src = tempCanvas.toDataURL();
}

function getPixel(data, x, y, w) {
    const i = (y * w + x) * 4;
    return { r: data[i], g: data[i + 1], b: data[i + 2], a: data[i + 3] };
}

cleanerTolerance.addEventListener('input', () => {
    toleranceVal.textContent = cleanerTolerance.value;
});

cleanerTolerance.addEventListener('change', updateProcessedImage);
enableCleaner.addEventListener('change', updateProcessedImage);

function renderSource() {
    if (!processedSourceImage) return;
    sourceCtx.clearRect(0, 0, sourceCanvas.width, sourceCanvas.height);
    sourceCtx.drawImage(processedSourceImage, 0, 0);
    if (isSelecting) {
        sourceCtx.strokeStyle = '#89b4fa';
        sourceCtx.lineWidth = 2;
        sourceCtx.strokeRect(selectionStart.x, selectionStart.y, selectionEnd.x - selectionStart.x, selectionEnd.y - selectionStart.y);
        sourceCtx.fillStyle = 'rgba(137, 180, 250, 0.2)';
        sourceCtx.fillRect(selectionStart.x, selectionStart.y, selectionEnd.x - selectionStart.x, selectionEnd.y - selectionStart.y);
    }
}

sourceCanvas.addEventListener('mousedown', (e) => {
    if (!sourceImage) return;
    isSelecting = true;
    const rect = sourceCanvas.getBoundingClientRect();
    selectionStart = { x: e.clientX - rect.left, y: e.clientY - rect.top };
    selectionEnd = { ...selectionStart };
});

window.addEventListener('mousemove', (e) => {
    if (isSelecting) {
        const rect = sourceCanvas.getBoundingClientRect();
        selectionEnd = { x: e.clientX - rect.left, y: e.clientY - rect.top };
        renderSource();
    }
});

window.addEventListener('mouseup', () => {
    if (isSelecting) {
        isSelecting = false;
        extractFrame();
        renderSource();
    }
});

function extractFrame() {
    const x = Math.min(selectionStart.x, selectionEnd.x);
    const y = Math.min(selectionStart.y, selectionEnd.y);
    const w = Math.abs(selectionEnd.x - selectionStart.x);
    const h = Math.abs(selectionEnd.y - selectionStart.y);
    if (w < 5 || h < 5) return;

    const frameCanvas = document.createElement('canvas');
    frameCanvas.width = w;
    frameCanvas.height = h;
    const fCtx = frameCanvas.getContext('2d');
    // Draw from the PROCESSED image to get the cleaned frame
    fCtx.drawImage(processedSourceImage, x, y, w, h, 0, 0, w, h);

    const newFrame = {
        canvas: frameCanvas,
        x: (frames.length % 4) * 200 + 50,
        y: Math.floor(frames.length / 4) * 200 + 50,
        w: w,
        h: h,
        scale: 1.0,
        anchorX: w / 2, // Default anchor is center
        anchorY: h / 2
    };
    frames.push(newFrame);
    updateFrameList();
    updateMiniList();
}

// --- Main Canvas Logic ---
function renderMain() {
    mainCtx.clearRect(0, 0, 1024, 1024);
    if (selectedFrameIndex !== -1) {
        frameControlPanel.style.display = 'flex';
        frameScaleSlider.value = frames[selectedFrameIndex].scale;
        frameScaleVal.textContent = frames[selectedFrameIndex].scale.toFixed(1);
    } else {
        frameControlPanel.style.display = 'none';
    }

    if (gridToggle.checked) {
        mainCtx.strokeStyle = '#333';
        mainCtx.lineWidth = 1;
        for (let i = 0; i <= 1024; i += 64) {
            mainCtx.beginPath(); mainCtx.moveTo(i, 0); mainCtx.lineTo(i, 1024); mainCtx.stroke();
            mainCtx.beginPath(); mainCtx.moveTo(0, i); mainCtx.lineTo(1024, i); mainCtx.stroke();
        }
    }

    frames.forEach((frame, index) => {
        const fw = frame.w * frame.scale;
        const fh = frame.h * frame.scale;
        mainCtx.drawImage(frame.canvas, frame.x, frame.y, fw, fh);
        
        // Draw Anchor Point (Red Dot)
        mainCtx.fillStyle = 'red';
        mainCtx.beginPath();
        mainCtx.arc(frame.x + frame.anchorX * frame.scale, frame.y + frame.anchorY * frame.scale, 4, 0, Math.PI * 2);
        mainCtx.fill();

        if (index === selectedFrameIndex) {
            mainCtx.strokeStyle = '#f38ba8';
            mainCtx.lineWidth = 2;
            mainCtx.strokeRect(frame.x, frame.y, fw, fh);
            mainCtx.fillStyle = '#f38ba8';
            mainCtx.fillRect(frame.x + fw - HANDLE_SIZE/2, frame.y + fh - HANDLE_SIZE/2, HANDLE_SIZE, HANDLE_SIZE);
        }
    });
}

mainCanvas.addEventListener('mousedown', (e) => {
    const rect = mainCanvas.getBoundingClientRect();
    const mouseX = (e.clientX - rect.left) * (1024 / rect.width);
    const mouseY = (e.clientY - rect.top) * (1024 / rect.height);

    if (selectedFrameIndex !== -1) {
        const f = frames[selectedFrameIndex];
        const fw = f.w * f.scale;
        const fh = f.h * f.scale;
        // Check resize handle
        if (Math.abs(mouseX - (f.x + fw)) < HANDLE_SIZE && Math.abs(mouseY - (f.y + fh)) < HANDLE_SIZE) {
            isResizing = true;
            return;
        }
        // Check anchor set (click inside frame)
        if (mouseX >= f.x && mouseX <= f.x + fw && mouseY >= f.y && mouseY <= f.y + fh) {
            f.anchorX = (mouseX - f.x) / f.scale;
            f.anchorY = (mouseY - f.y) / f.scale;
            renderMain();
            return;
        }
    }

    selectedFrameIndex = -1;
    for (let i = frames.length - 1; i >= 0; i--) {
        const f = frames[i];
        if (mouseX >= f.x && mouseX <= f.x + f.w * f.scale && mouseY >= f.y && mouseY <= f.y + f.h * f.scale) {
            selectedFrameIndex = i;
            isDragging = true;
            dragOffset = { x: mouseX - f.x, y: mouseY - f.y };
            updateFrameList();
            break;
        }
    }
    renderMain();
});

mainCanvas.addEventListener('mousemove', (e) => {
    const rect = mainCanvas.getBoundingClientRect();
    const mouseX = (e.clientX - rect.left) * (1024 / rect.width);
    const mouseY = (e.clientY - rect.top) * (1024 / rect.height);

    if (isResizing && selectedFrameIndex !== -1) {
        const f = frames[selectedFrameIndex];
        f.scale = Math.max(0.1, Math.min(5.0, Math.max((mouseX - f.x) / f.w, (mouseY - f.y) / f.h)));
        renderMain();
    } else if (isDragging && selectedFrameIndex !== -1) {
        const f = frames[selectedFrameIndex];
        f.x = mouseX - dragOffset.x;
        f.y = mouseY - dragOffset.y;
        if (gridToggle.checked) {
            f.x = Math.round(f.x / 16) * 16;
            f.y = Math.round(f.y / 16) * 16;
        }
        renderMain();
    }
});

window.addEventListener('mouseup', () => { isDragging = false; isResizing = false; });

autoAlignBtn.addEventListener('click', () => {
    if (frames.length === 0) return;
    const cols = parseInt(gridColsSelect.value);
    const rows = parseInt(gridRowsSelect.value);
    const cellW = 1024 / cols;
    const cellH = 1024 / rows;
    
    frames.forEach((f, i) => {
        const col = i % cols;
        const row = Math.floor(i / cols);
        
        // Don't place beyond M rows if there are too many frames
        if (row >= rows) return;

        const cellCenterX = col * cellW + cellW / 2;
        const cellCenterY = row * cellH + cellH / 2;
        
        // Align anchor point to cell center
        f.x = cellCenterX - f.anchorX * f.scale;
        f.y = cellCenterY - f.anchorY * f.scale;
    });
    renderMain();
});

// --- UI Helpers ---
function updateFrameList() {
    framesUl.innerHTML = '';
    frames.forEach((f, i) => {
        const li = document.createElement('li');
        if (i === selectedFrameIndex) li.classList.add('selected');
        li.innerHTML = `<img src="${f.canvas.toDataURL()}"><span>帧 ${i+1} (${f.w}x${f.h})</span>`;
        li.addEventListener('click', () => { selectedFrameIndex = i; renderMain(); updateFrameList(); });
        framesUl.appendChild(li);
    });
}

function updateMiniList() {
    miniFrameList.innerHTML = '';
    frames.forEach(f => {
        const cvs = document.createElement('canvas');
        cvs.width = f.w; cvs.height = f.h;
        cvs.getContext('2d').drawImage(f.canvas, 0, 0);
        miniFrameList.appendChild(cvs);
    });
}

clearCacheBtn.addEventListener('click', () => { frames = []; selectedFrameIndex = -1; updateFrameList(); updateMiniList(); renderMain(); });
deleteFrameBtn.addEventListener('click', () => { if (selectedFrameIndex !== -1) { frames.splice(selectedFrameIndex, 1); selectedFrameIndex = -1; updateFrameList(); updateMiniList(); renderMain(); } });
gridToggle.addEventListener('change', renderMain);
frameScaleSlider.addEventListener('input', () => { if (selectedFrameIndex !== -1) { frames[selectedFrameIndex].scale = parseFloat(frameScaleSlider.value); frameScaleVal.textContent = frames[selectedFrameIndex].scale.toFixed(1); renderMain(); } });

// --- Preview Logic ---
function animate(time) {
    const fps = parseInt(fpsSlider.value);
    const interval = 1000 / fps;
    if (time - lastFrameTime > interval) {
        lastFrameTime = time;
        if (frames.length > 0) {
            currentPreviewFrame = (currentPreviewFrame + 1) % frames.length;
            const f = frames[currentPreviewFrame];
            previewCtx.clearRect(0, 0, 256, 256);
            const s = Math.min(200 / f.w, 200 / f.h);
            previewCtx.drawImage(f.canvas, 128 - f.anchorX * s, 128 - f.anchorY * s, f.w * s, f.h * s);
            // Draw crosshair at center of preview to show anchor alignment
            previewCtx.strokeStyle = 'rgba(255,0,0,0.3)';
            previewCtx.beginPath(); previewCtx.moveTo(128, 118); previewCtx.lineTo(128, 138); previewCtx.stroke();
            previewCtx.beginPath(); previewCtx.moveTo(118, 128); previewCtx.lineTo(138, 128); previewCtx.stroke();
        }
    }
    requestAnimationFrame(animate);
}
requestAnimationFrame(animate);
fpsSlider.addEventListener('input', () => { fpsVal.textContent = fpsSlider.value; });

downloadBtn.addEventListener('click', () => {
    const exportCanvas = document.createElement('canvas');
    exportCanvas.width = 1024; exportCanvas.height = 1024;
    const exCtx = exportCanvas.getContext('2d');
    frames.forEach(f => { exCtx.drawImage(f.canvas, f.x, f.y, f.w * f.scale, f.h * f.scale); });
    const link = document.createElement('a');
    link.download = 'spritesheet_composed.png';
    link.href = exportCanvas.toDataURL('image/png');
    link.click();
});
