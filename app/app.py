from flask import Flask, request, redirect, url_for, send_from_directory, render_template, jsonify, send_file
import os, io, zipfile, shutil

app = Flask(__name__)
UPLOAD_FOLDER = '/shared_files'
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER

def get_tree(directory):
    tree = []
    for item in os.listdir(directory):
        if item == "untitled.txt":
            continue
        path = os.path.join(directory, item)
        if os.path.isdir(path):
            tree.append({
                'type': 'directory',
                'name': item,
                'children': get_tree(path)
            })
        else:
            tree.append({'type': 'file', 'name': item})
    return tree

@app.route('/')
def index():
    tree = get_tree(app.config['UPLOAD_FOLDER'])
    return render_template('index.html', tree=tree)

@app.route('/upload', methods=['POST'])
def upload_file():
    for file in request.files.getlist("files"):
        if file and file.filename:
            save_path = os.path.join(app.config['UPLOAD_FOLDER'], file.filename)
            os.makedirs(os.path.dirname(save_path), exist_ok=True)
            file.save(save_path)
    return ('', 204)

@app.route('/files/<path:filename>')
def uploaded_file(filename):
    return send_from_directory(app.config['UPLOAD_FOLDER'], filename)

# Updated download_folder route to create a temporary in-memory ZIP archive.
@app.route('/download_folder/<path:foldername>')
def download_folder(foldername):
    folder_path = os.path.join(app.config['UPLOAD_FOLDER'], foldername)
    if not os.path.exists(folder_path):
        return jsonify({"error": "Folder not found"}), 404

    memory_file = io.BytesIO()
    with zipfile.ZipFile(memory_file, 'w', zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(folder_path):
            for file in files:
                abs_filename = os.path.join(root, file)
                arcname = os.path.relpath(abs_filename, os.path.join(folder_path, '..'))
                zf.write(abs_filename, arcname)
    memory_file.seek(0)
    return send_file(memory_file, mimetype='application/zip', as_attachment=True,
                     download_name=f"{os.path.basename(foldername)}.zip")

@app.route('/delete_folder/<path:foldername>', methods=['POST'])
def delete_folder(foldername):
    folder_path = os.path.join(app.config['UPLOAD_FOLDER'], foldername)
    if os.path.exists(folder_path):
        shutil.rmtree(folder_path)
    return redirect(url_for('index'))

@app.route('/download_file/<path:filepath>')
def download_file(filepath):
    return send_from_directory(app.config['UPLOAD_FOLDER'], filepath, as_attachment=True)

@app.route('/delete_file/<path:filepath>', methods=['POST'])
def delete_file(filepath):
    full_path = os.path.join(app.config['UPLOAD_FOLDER'], filepath)
    if os.path.isfile(full_path):
        os.remove(full_path)
    return redirect(url_for('index'))

# If content is empty, create an empty file without error.
@app.route('/create_local_text', methods=['POST'])
def create_local_text():
    content = request.form.get("content")
    file_path = os.path.join(app.config['UPLOAD_FOLDER'], "untitled.txt")
    with open(file_path, 'w') as f:
        f.write(content if content is not None else "")
    return redirect(url_for('index'))

@app.route('/read_local_text')
def read_local_text():
    file_path = os.path.join(app.config['UPLOAD_FOLDER'], "untitled.txt")
    if os.path.exists(file_path):
        with open(file_path, 'r') as f:
            content = f.read()
    else:
        content = ""
    return render_template('local_text.html', content=content)

if __name__ == "__main__":
    os.makedirs(UPLOAD_FOLDER, exist_ok=True)
    app.run(host='0.0.0.0', port=5000)
