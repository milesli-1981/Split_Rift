from flask import Flask, render_template, request, send_from_directory, jsonify
import os
import cv2
import numpy as np
import base64
import sys

# 导入现有的处理逻辑
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from sprite_packer import clean_sprite, cv2_imread, cv2_imwrite
from watermark_remover import remove_watermark

app = Flask(__name__)
UPLOAD_FOLDER = os.path.join(os.path.dirname(__file__), 'static', 'uploads')
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/upload', methods=['POST'])
def upload_file():
    if 'file' not in request.files:
        return jsonify({'error': 'No file part'})
    file = request.files['file']
    if file.filename == '':
        return jsonify({'error': 'No selected file'})
    
    filename = 'current_image.png'
    filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
    file.save(filepath)
    return jsonify({'url': '/static/uploads/' + filename})

@app.route('/process/auto_clean', methods=['POST'])
def auto_clean():
    filepath = os.path.join(app.config['UPLOAD_FOLDER'], 'current_image.png')
    img = cv2_imread(filepath)
    if img is None:
        return jsonify({'error': 'Image not found'})
    
    # 获取容差参数
    tolerance = int(request.json.get('tolerance', 20))
    cleaned = clean_sprite(img, tolerance=tolerance)
    
    output_path = os.path.join(app.config['UPLOAD_FOLDER'], 'current_image.png')
    cv2_imwrite(output_path, cleaned)
    return jsonify({'url': '/static/uploads/current_image.png?t=' + str(os.path.getmtime(output_path))})

@app.route('/save_mask', methods=['POST'])
def save_mask():
    data = request.json.get('image') # base64 image from canvas
    if not data:
        return jsonify({'error': 'No image data'})
    
    header, encoded = data.split(",", 1)
    data = base64.b64decode(encoded)
    
    output_path = os.path.join(app.config['UPLOAD_FOLDER'], 'current_image.png')
    with open(output_path, "wb") as f:
        f.write(data)
    
    return jsonify({'success': True})

if __name__ == '__main__':
    app.run(debug=True, port=5000, use_reloader=False)
