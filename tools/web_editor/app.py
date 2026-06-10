import os
import base64
import cv2
import numpy as np
from flask import Flask, render_template, request, jsonify

app = Flask(__name__)
app.config['UPLOAD_FOLDER'] = os.path.join(os.path.dirname(__file__), 'temp_uploads')
os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/save_mask', methods=['POST'])
def save_mask():
    data = request.json
    image_data = data.get('image')
    if image_data:
        return jsonify({'success': True, 'message': 'Image received on server'})
    return jsonify({'success': False})

@app.route('/process_video', methods=['POST'])
def process_video():
    if 'video' not in request.files:
        return jsonify({'success': False, 'error': 'No video file'})
    
    video_file = request.files['video']
    start_time = float(request.form.get('start', 0))
    end_time = float(request.form.get('end', 0))
    target_fps = int(request.form.get('fps', 10))
    
    video_path = os.path.join(app.config['UPLOAD_FOLDER'], video_file.filename)
    video_file.save(video_path)
    
    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    
    frames = []
    current_time = start_time
    
    while current_time <= end_time:
        frame_idx = int(current_time * fps)
        cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
        ret, frame = cap.read()
        if not ret:
            break
            
        # Convert to PNG base64
        _, buffer = cv2.imencode('.png', frame)
        frame_base64 = base64.b64encode(buffer).decode('utf-8')
        frames.append(f"data:image/png;base64,{frame_base64}")
        
        current_time += 1.0 / target_fps
        
    cap.release()
    os.remove(video_path) # Clean up
    
    return jsonify({'success': True, 'frames': frames})

if __name__ == '__main__':
    print("Sprite Master Integrated Editor starting at http://127.0.0.1:5000")
    app.run(debug=True, port=5000)
