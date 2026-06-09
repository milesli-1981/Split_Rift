const canvas = document.getElementById('editorCanvas');
const ctx = canvas.getContext('2d');
const fileInput = document.getElementById('fileInput');
const autoCleanBtn = document.getElementById('autoCleanBtn');
const eraserBtn = document.getElementById('eraserBtn');
const saveBtn = document.getElementById('saveBtn');
const downloadBtn = document.getElementById('downloadBtn');
const brushSizeInput = document.getElementById('brushSize');
const toleranceInput = document.getElementById('tolerance');

let isDrawing = false;
let currentTool = 'none';
let img = new Image();

// 加载图片
fileInput.addEventListener('change', (e) => {
    const file = e.target.files[0];
    const formData = new FormData();
    formData.append('file', file);

    fetch('/upload', {
        method: 'POST',
        body: formData
    })
    .then(res => res.json())
    .then(data => {
        loadImage(data.url);
    });
});

function loadImage(url) {
    img.onload = () => {
        canvas.width = img.width;
        canvas.height = img.height;
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        ctx.drawImage(img, 0, 0);
    };
    img.src = url;
}

// 自动去底
autoCleanBtn.addEventListener('click', () => {
    fetch('/process/auto_clean', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ tolerance: toleranceInput.value })
    })
    .then(res => res.json())
    .then(data => {
        loadImage(data.url);
    });
});

// 橡皮擦工具
eraserBtn.addEventListener('click', () => {
    currentTool = currentTool === 'eraser' ? 'none' : 'eraser';
    eraserBtn.classList.toggle('active', currentTool === 'eraser');
});

canvas.addEventListener('mousedown', startDrawing);
canvas.addEventListener('mousemove', draw);
canvas.addEventListener('mouseup', stopDrawing);
canvas.addEventListener('mouseout', stopDrawing);

function startDrawing(e) {
    if (currentTool !== 'eraser') return;
    isDrawing = true;
    draw(e);
}

function draw(e) {
    if (!isDrawing || currentTool !== 'eraser') return;

    const rect = canvas.getBoundingClientRect();
    const x = (e.clientX - rect.left) * (canvas.width / rect.width);
    const y = (e.clientY - rect.top) * (canvas.height / rect.height);

    ctx.globalCompositeOperation = 'destination-out';
    ctx.beginPath();
    ctx.arc(x, y, brushSizeInput.value / 2, 0, Math.PI * 2);
    ctx.fill();
}

function stopDrawing() {
    isDrawing = false;
}

// 保存到服务器
saveBtn.addEventListener('click', () => {
    const dataURL = canvas.toDataURL('image/png');
    fetch('/save_mask', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ image: dataURL })
    })
    .then(res => res.json())
    .then(data => {
        if (data.success) alert('修改已应用到当前工作文件');
    });
});

// 下载
downloadBtn.addEventListener('click', () => {
    const link = document.createElement('a');
    link.download = 'sprite_edited.png';
    link.href = canvas.toDataURL('image/png');
    link.click();
});
