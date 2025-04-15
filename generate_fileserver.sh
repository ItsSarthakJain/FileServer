#!/bin/bash

# Define variables
IMAGE_NAME="nginx-flask-fileserver"
CONTAINER_NAME="nginx-flask-fileserver"
HOST_PORT=8080
SHARED_DIR="FileSharing"

# Stop and remove any existing container
if [ "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
    docker stop $CONTAINER_NAME && docker rm $CONTAINER_NAME
fi

mkdir -p "$(pwd)/$SHARED_DIR"

# ---------------- Dockerfile ----------------
cat <<'EOF' > Dockerfile
FROM python:3.9-slim
RUN apt-get update && apt-get install -y nginx && apt-get clean

COPY nginx.conf /etc/nginx/sites-available/default
RUN pip install flask
COPY app /app
WORKDIR /app
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80
CMD ["/entrypoint.sh"]
EOF

# ---------------- Nginx config ----------------
cat <<'EOF' > nginx.conf
server {
    listen 80;
    server_name localhost;
    client_max_body_size 0;

    location / {
        proxy_pass http://localhost:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /files/ {
        autoindex on;
        alias /shared_files/;
    }
}
EOF

# ---------------- Flask App (no change) ----------------
# (omitted here for brevity, same as your original `app/app.py`)

# ---------------- HTML Template with drag-drop fix ----------------
mkdir -p app/templates
cat <<'EOF' > app/templates/index.html
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>File Server</title>
  <style>
    body { font-family: Arial; padding: 20px; }
    ul.directory-list { list-style: none; padding-left: 20px; }
    .name { display: inline-block; width: 60%; }
    .actions { display: inline-block; width: 35%; text-align: right; }
    button { background: #f44336; color: white; border: none; padding: 5px 10px; border-radius: 4px; cursor: pointer; }
    button:hover { background-color: #d32f2f; }
    a { color: #0073e6; font-weight: bold; text-decoration: none; }
    a:hover { text-decoration: underline; }
    .folder-contents { margin-left: 20px; display: none; }
  </style>
</head>
<body>
  <h1>File Server</h1>

  <!-- Local Text -->
  <form action="/create_local_text" method="post" id="edit-form">
    <textarea name="content" style="width:70%;height:100px;"></textarea>
    <button type="submit">Save Text</button>
    <button type="button" onclick="window.open('/read_local_text', '_blank')">Read Text</button>
  </form>
  <hr>

  {% macro render_tree(tree, base_path="") %}
    <ul class="directory-list">
      {% for item in tree %}
        <li>
          {% if item.type == 'directory' %}
            {% set full_path = base_path + item.name %}
            <div>
              <span class="name">
                <a href="javascript:void(0);" onclick="toggleFolder('{{ full_path }}');">{{ item.name }}/</a>
              </span>
              <span class="actions">
                <a href="/download_folder/{{ full_path }}">Download</a>
                <form action="/delete_folder/{{ full_path }}" method="post" style="display:inline;">
                  <button type="submit">Delete</button>
                </form>
              </span>
            </div>
            <div id="folder-{{ full_path }}" class="folder-contents">
              {{ render_tree(item.children, full_path + '/') }}
            </div>
          {% else %}
            {% set full_path = base_path + item.name %}
            <div>
              <span class="name">
                <a href="/files/{{ full_path }}">{{ item.name }}</a>
              </span>
              <span class="actions">
                <a href="/download_file/{{ full_path }}">Download</a>
                <form action="/delete_file/{{ full_path }}" method="post" style="display:inline;">
                  <button type="submit">Delete</button>
                </form>
              </span>
            </div>
          {% endif %}
        </li>
      {% endfor %}
    </ul>
  {% endmacro %}

  {{ render_tree(tree) }}

  <hr>
  <h2>Upload Files or Folders</h2>
  <form id="upload-form">
    <input type="file" id="file-input" name="files" multiple webkitdirectory directory hidden>
    <div id="drop-zone" style="border:2px dashed #ccc; padding:40px; text-align:center; cursor:pointer;">
      Click or drag folders/files here
    </div>
    <ul id="file-list"></ul>
    <button type="button" id="upload-button">Upload</button>
  </form>

  <script>
    function toggleFolder(id) {
      const el = document.getElementById('folder-' + id);
      if (el) {
        el.style.display = el.style.display === 'none' ? 'block' : 'none';
      }
    }

    const dropZone = document.getElementById('drop-zone');
    const fileInput = document.getElementById('file-input');
    const fileList = document.getElementById('file-list');
    let filesToUpload = [];

    dropZone.onclick = () => fileInput.click();

    const showFiles = (files) => {
      fileList.innerHTML = '';
      filesToUpload = Array.from(files);
      filesToUpload.forEach(f => {
        const li = document.createElement('li');
        li.textContent = f.webkitRelativePath || f.name;
        fileList.appendChild(li);
      });
    };

    fileInput.onchange = () => showFiles(fileInput.files);

    dropZone.ondragover = e => { e.preventDefault(); dropZone.style.background = '#f0f8ff'; };
    dropZone.ondragleave = () => { dropZone.style.background = ''; };
    dropZone.ondrop = async (e) => {
      e.preventDefault();
      dropZone.style.background = '';

      const dt = new DataTransfer();
      const items = e.dataTransfer.items;
      const files = [];

      async function traverseFileTree(item, path = '') {
        return new Promise((resolve) => {
          if (item.isFile) {
            item.file(file => {
              const newFile = new File([file], path + file.name, { type: file.type });
              files.push(newFile);
              resolve();
            });
          } else if (item.isDirectory) {
            const dirReader = item.createReader();
            dirReader.readEntries(async (entries) => {
              for (const entry of entries) {
                await traverseFileTree(entry, path + item.name + '/');
              }
              resolve();
            });
          }
        });
      }

      const traversePromises = [];
      for (const item of items) {
        const entry = item.webkitGetAsEntry();
        if (entry) {
          traversePromises.push(traverseFileTree(entry));
        }
      }

      await Promise.all(traversePromises);

      for (const file of files) {
        dt.items.add(file);
      }

      fileInput.files = dt.files;
      showFiles(fileInput.files);
    };

    document.getElementById('upload-button').onclick = () => {
      if (!filesToUpload.length) return alert('No files selected');
      const formData = new FormData();
      filesToUpload.forEach(f => formData.append("files", f, f.webkitRelativePath || f.name));
      fetch("/upload", { method: "POST", body: formData }).then(r => r.ok && location.reload());
    };
  </script>
</body>
</html>
EOF


# ---------------- HTML Template: index.html with recursive macro ----------------
cat <<'EOF' > app/templates/index.html
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>File Server</title>
  <style>
    body { font-family: Arial; padding: 20px; }
    ul.directory-list { list-style: none; padding-left: 20px; }
    .name { display: inline-block; width: 60%; }
    .actions { display: inline-block; width: 35%; text-align: right; }
    button { background: #f44336; color: white; border: none; padding: 5px 10px; border-radius: 4px; cursor: pointer; }
    button:hover { background-color: #d32f2f; }
    a { color: #0073e6; font-weight: bold; text-decoration: none; }
    a:hover { text-decoration: underline; }
    .folder-contents { margin-left: 20px; display: none; }
  </style>
</head>
<body>
  <h1>File Server</h1>

  <!-- Local Text -->
  <form action="/create_local_text" method="post" id="edit-form">
    <textarea name="content" style="width:70%;height:100px;"></textarea>
    <button type="submit">Save Text</button>
    <button type="button" onclick="window.open('/read_local_text', '_blank')">Read Text</button>
  </form>
  <hr>

  {% macro render_tree(tree, base_path="") %}
    <ul class="directory-list">
      {% for item in tree %}
        <li>
          {% if item.type == 'directory' %}
            {% set full_path = base_path + item.name %}
            <div>
              <span class="name">
                <a href="javascript:void(0);" onclick="toggleFolder('{{ full_path }}');">{{ item.name }}/</a>
              </span>
              <span class="actions">
                <a href="/download_folder/{{ full_path }}">Download</a>
                <form action="/delete_folder/{{ full_path }}" method="post" style="display:inline;">
                  <button type="submit">Delete</button>
                </form>
              </span>
            </div>
            <div id="folder-{{ full_path }}" class="folder-contents">
              {{ render_tree(item.children, full_path + '/') }}
            </div>
          {% else %}
            {% set full_path = base_path + item.name %}
            <div>
              <span class="name">
                <a href="/files/{{ full_path }}">{{ item.name }}</a>
              </span>
              <span class="actions">
                <a href="/download_file/{{ full_path }}">Download</a>
                <form action="/delete_file/{{ full_path }}" method="post" style="display:inline;">
                  <button type="submit">Delete</button>
                </form>
              </span>
            </div>
          {% endif %}
        </li>
      {% endfor %}
    </ul>
  {% endmacro %}

  {{ render_tree(tree) }}

  <hr>
  <h2>Upload Files or Folders</h2>
  <form id="upload-form">
    <input type="file" id="file-input" name="files" multiple webkitdirectory directory hidden>
    <div id="drop-zone" style="border:2px dashed #ccc; padding:40px; text-align:center; cursor:pointer;">
      Click or drag folders/files here
    </div>
    <ul id="file-list"></ul>
    <button type="button" id="upload-button">Upload</button>
  </form>

  <script>
    function toggleFolder(id) {
      const el = document.getElementById('folder-' + id);
      if (el) {
        el.style.display = el.style.display === 'none' ? 'block' : 'none';
      }
    }

    const dropZone = document.getElementById('drop-zone');
    const fileInput = document.getElementById('file-input');
    const fileList = document.getElementById('file-list');
    let filesToUpload = [];

    dropZone.onclick = () => fileInput.click();

    const showFiles = (files) => {
      fileList.innerHTML = '';
      filesToUpload = Array.from(files);
      filesToUpload.forEach(f => {
        const li = document.createElement('li');
        li.textContent = f.webkitRelativePath || f.name;
        fileList.appendChild(li);
      });
    };

    fileInput.onchange = () => showFiles(fileInput.files);

    dropZone.ondragover = e => { e.preventDefault(); dropZone.style.background = '#f0f8ff'; };
    dropZone.ondragleave = () => { dropZone.style.background = ''; };
    dropZone.ondrop = async (e) => {
      e.preventDefault();
      dropZone.style.background = '';
      const dt = new DataTransfer();
      const items = e.dataTransfer.items;
      const promises = [];

      const traverse = (item, path = '') => new Promise(resolve => {
        if (item.isFile) {
          item.file(file => {
            file.webkitRelativePath = path + file.name;
            dt.items.add(file);
            resolve();
          });
        } else if (item.isDirectory) {
          const dirReader = item.createReader();
          dirReader.readEntries(async entries => {
            for (const entry of entries) {
              await traverse(entry, path + item.name + '/');
            }
            resolve();
          });
        }
      });

      for (const item of items) {
        const entry = item.webkitGetAsEntry();
        if (entry) promises.push(traverse(entry));
      }

      await Promise.all(promises);
      fileInput.files = dt.files;
      showFiles(fileInput.files);
    };

    document.getElementById('upload-button').onclick = () => {
      if (!filesToUpload.length) return alert('No files selected');
      const formData = new FormData();
      filesToUpload.forEach(f => formData.append("files", f, f.webkitRelativePath || f.name));
      fetch("/upload", { method: "POST", body: formData }).then(r => r.ok && location.reload());
    };
  </script>
</body>
</html>
EOF

# ---------------- Updated Local Text with Top Buttons ----------------
cat <<'EOF' > app/templates/local_text.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Local Text Editor</title>
  <style>
    body {
      font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
      background: #f9fafb;
      margin: 0;
      padding: 0;
      color: #1f2937;
    }
    .container {
      max-width: 900px;
      margin: 40px auto;
      background: #ffffff;
      padding: 30px;
      border-radius: 12px;
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.05);
    }
    h1 {
      font-size: 22px;
      font-weight: 600;
      margin-bottom: 16px;
    }
    pre, textarea {
      background-color: #f3f4f6;
      padding: 20px;
      border-radius: 8px;
      overflow-x: auto;
      white-space: pre-wrap;
      word-wrap: break-word;
      font-family: Consolas, monospace;
      font-size: 15px;
      width: 100%;
      box-sizing: border-box;
      border: none;
      margin-top: 10px;
    }
    textarea {
      resize: vertical;
      display: none;
      min-height: 200px;
    }
    .buttons {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      margin-bottom: 10px;
    }
    .buttons button, .buttons a.back-link {
      background: #e5e7eb;
      border: none;
      padding: 6px 12px;
      border-radius: 6px;
      cursor: pointer;
      font-size: 13px;
      font-weight: 500;
      color: #111827;
      transition: background 0.3s;
      text-decoration: none;
    }
    .buttons button:hover, .buttons a.back-link:hover {
      background: #d1d5db;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>📝 Local Text Editor</h1>

    <div class="buttons">
      <button onclick="copyText()">Copy</button>
      <button onclick="toggleEdit()" id="edit-btn">Edit</button>
      <button type="submit" form="edit-form" style="display: none;" id="save-btn">Save</button>
      <button onclick="clearText()" style="display: none;" id="clear-btn">Clear All</button>
      <a href="/" class="back-link">← Back</a>
    </div>

    <pre id="text-view">{{ content }}</pre>
    <form id="edit-form" action="/create_local_text" method="post">
      <textarea id="text-edit" name="content">{{ content }}</textarea>
    </form>
  </div>

  <script>
    let isEditing = false;
    const textView = document.getElementById('text-view');
    const textEdit = document.getElementById('text-edit');
    const editBtn = document.getElementById('edit-btn');
    const saveBtn = document.getElementById('save-btn');
    const clearBtn = document.getElementById('clear-btn');

    function toggleEdit() {
      if (isEditing) {
        textView.style.display = 'block';
        textEdit.style.display = 'none';
        saveBtn.style.display = 'none';
        clearBtn.style.display = 'none';
        editBtn.textContent = 'Edit';
      } else {
        textView.style.display = 'none';
        textEdit.style.display = 'block';
        saveBtn.style.display = 'inline-block';
        clearBtn.style.display = 'inline-block';
        editBtn.textContent = 'Cancel';
      }
      isEditing = !isEditing;
    }

    function copyText() {
      navigator.clipboard.writeText(textView.textContent);
      alert('Text copied to clipboard!');
    }

    function clearText() {
      if (confirm('Are you sure you want to clear all text?')) {
        textEdit.value = '';
      }
    }
  </script>
</body>
</html>
EOF

# ---------------- Entrypoint ----------------
cat <<'EOF' > entrypoint.sh
#!/bin/bash
python /app/app.py &
nginx -g 'daemon off;'
EOF

chmod +x entrypoint.sh

# ---------------- Build & Run Docker Container ----------------
docker build -t $IMAGE_NAME .
docker run -d --rm \
    -p $HOST_PORT:80 \
    --name $CONTAINER_NAME \
    -v "$(pwd)/$SHARED_DIR":/shared_files \
    $IMAGE_NAME

echo "✅ File server is running at: http://localhost:$HOST_PORT"
echo "📁 Shared folder: $(pwd)/$SHARED_DIR"
