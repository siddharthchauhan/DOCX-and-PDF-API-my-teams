#!/bin/bash
# Linux Deployment Script for Markdown Render API
# Run this script on your Linux server to set up the API

set -e  # Exit on any error

echo "🚀 Starting Markdown Render API deployment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root. Please run as a regular user with sudo privileges."
   exit 1
fi

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    print_error "Python 3 is not installed. Please install Python 3.8 or higher."
    exit 1
fi

# Check Python version
PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
REQUIRED_VERSION="3.8"

if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$PYTHON_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]; then
    print_error "Python $RETHON_VERSION is installed, but Python $REQUIRED_VERSION or higher is required."
    exit 1
fi

print_status "Python $PYTHON_VERSION detected ✓"

# Install system dependencies
print_status "Installing system dependencies..."

if command -v apt-get &> /dev/null; then
    # Ubuntu/Debian
    sudo apt-get update
    sudo apt-get install -y python3-pip python3-venv python3-dev build-essential libssl-dev libffi-dev
    
    # Optional dependencies for enhanced features
    print_warning "Installing optional dependencies for enhanced PDF rendering..."
    sudo apt-get install -y libpango1.0-dev libharfbuzz-dev libglib2.0-dev libcairo2-dev || print_warning "Some optional dependencies failed to install"
    
    print_warning "Installing Pandoc for DOCX generation..."
    sudo apt-get install -y pandoc || print_warning "Pandoc installation failed"
    
elif command -v yum &> /dev/null; then
    # CentOS/RHEL
    sudo yum install -y python3-pip python3-devel gcc openssl-devel libffi-devel
    
    # Optional dependencies
    print_warning "Installing optional dependencies..."
    sudo yum install -y pango-devel harfbuzz-devel glib2-devel cairo-devel || print_warning "Some optional dependencies failed to install"
    
    print_warning "Installing Pandoc..."
    sudo yum install -y pandoc || print_warning "Pandoc installation failed"
    
elif command -v dnf &> /dev/null; then
    # Fedora
    sudo dnf install -y python3-pip python3-devel gcc openssl-devel libffi-devel
    
    # Optional dependencies
    print_warning "Installing optional dependencies..."
    sudo dnf install -y pango-devel harfbuzz-devel glib2-devel cairo-devel || print_warning "Some optional dependencies failed to install"
    
    print_warning "Installing Pandoc..."
    sudo dnf install -y pandoc || print_warning "Pandoc installation failed"
else
    print_warning "Unknown package manager. Please install dependencies manually."
fi

# Install Node.js and Mermaid CLI (optional)
print_status "Installing Node.js and Mermaid CLI..."

if ! command -v node &> /dev/null; then
    print_warning "Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    
    if command -v apt-get &> /dev/null; then
        sudo apt-get install -y nodejs
    elif command -v yum &> /dev/null; then
        sudo yum install -y nodejs
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y nodejs
    fi
else
    print_status "Node.js already installed ✓"
fi

# Install Mermaid CLI
if command -v npm &> /dev/null; then
    print_status "Installing Mermaid CLI..."
    sudo npm install -g @mermaid-js/mermaid-cli || print_warning "Mermaid CLI installation failed"
else
    print_warning "npm not found, skipping Mermaid CLI installation"
fi

# Create project directory
PROJECT_DIR="$HOME/markdown-render-api"
print_status "Setting up project directory: $PROJECT_DIR"

if [ -d "$PROJECT_DIR" ]; then
    print_warning "Project directory already exists. Backing up..."
    mv "$PROJECT_DIR" "${PROJECT_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
fi

mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# Create virtual environment
print_status "Creating Python virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Upgrade pip
print_status "Upgrading pip..."
pip install --upgrade pip

# Install Python dependencies
print_status "Installing Python dependencies..."

# Core dependencies
pip install fastapi uvicorn pydantic python-multipart

# PDF generation
pip install reportlab
pip install weasyprint || print_warning "WeasyPrint installation failed (optional)"

# DOCX generation
pip install pypandoc python-docx html2docx

# Markdown processing
pip install markdown-it-py mdit-py-plugins

# Other dependencies
pip install pygments pillow requests python-dotenv

print_status "Python dependencies installed ✓"

# Create a simple startup script
print_status "Creating startup script..."
cat > start_api.sh << 'EOF'
#!/bin/bash
cd "$HOME/markdown-render-api"
source venv/bin/activate

# Check if API file exists
if [ ! -f "pdf_docx_api.py" ]; then
    echo "Error: pdf_docx_api.py not found in current directory"
    echo "Please copy your API file to: $HOME/markdown-render-api/"
    exit 1
fi

echo "🚀 Starting Markdown Render API..."
echo "📁 Working directory: $(pwd)"
echo "🐍 Python version: $(python --version)"
echo "🌐 Server will be available at: http://0.0.0.0:8000"
echo "📖 API documentation: http://0.0.0.0:8000/docs"
echo ""
echo "Press Ctrl+C to stop the server"
echo ""

# Start the API
uvicorn pdf_docx_api:app --host 0.0.0.0 --port 8000
EOF

chmod +x start_api.sh

# Create a systemd service file
print_status "Creating systemd service..."
sudo tee /etc/systemd/system/markdown-api.service > /dev/null << EOF
[Unit]
Description=Markdown Render API
After=network.target

[Service]
Type=exec
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
Environment=PATH=$PROJECT_DIR/venv/bin
ExecStart=$PROJECT_DIR/venv/bin/uvicorn pdf_docx_api:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Create a health check script
print_status "Creating health check script..."
cat > health_check.sh << 'EOF'
#!/bin/bash
API_URL="http://localhost:8000/health"
LOG_FILE="$HOME/markdown-render-api/health.log"

response=$(curl -s -o /dev/null -w "%{http_code}" $API_URL 2>/dev/null)

if [ $response -eq 200 ]; then
    echo "$(date): API is healthy" >> $LOG_FILE
    echo "✅ API is running"
else
    echo "$(date): API is down (HTTP $response)" >> $LOG_FILE
    echo "❌ API is not responding"
    
    # Try to restart the service
    if systemctl is-active --quiet markdown-api; then
        echo "🔄 Restarting service..."
        sudo systemctl restart markdown-api
        sleep 5
        
        # Check again
        response=$(curl -s -o /dev/null -w "%{http_code}" $API_URL 2>/dev/null)
        if [ $response -eq 200 ]; then
            echo "✅ API restarted successfully"
        else
            echo "❌ API restart failed"
        fi
    fi
fi
EOF

chmod +x health_check.sh

# Create a simple test script
print_status "Creating test script..."
cat > test_api.sh << 'EOF'
#!/bin/bash
echo "🧪 Testing Markdown Render API..."

# Test health endpoint
echo "Testing health endpoint..."
curl -s http://localhost:8000/health | python3 -m json.tool || echo "❌ Health check failed"

echo ""
echo "Testing PDF generation..."
curl -X POST "http://localhost:8000/render/pdf" \
     -H "Content-Type: application/json" \
     -d '{
         "markdown": "# Test Document\n\nThis is a test document with **bold text** and a table:\n\n| Feature | Status |\n|---------|--------|\n| PDF | ✅ Working |\n| DOCX | ✅ Working |",
         "filename": "test_document"
     }' \
     --output test_document.pdf

if [ -f "test_document.pdf" ]; then
    echo "✅ PDF generation test passed"
    rm test_document.pdf
else
    echo "❌ PDF generation test failed"
fi

echo ""
echo "Testing DOCX generation..."
curl -X POST "http://localhost:8000/render/docx" \
     -H "Content-Type: application/json" \
     -d '{
         "markdown": "# Test Document\n\nThis is a test document with **bold text** and a table:\n\n| Feature | Status |\n|---------|--------|\n| PDF | ✅ Working |\n| DOCX | ✅ Working |",
         "filename": "test_document"
     }' \
     --output test_document.docx

if [ -f "test_document.docx" ]; then
    echo "✅ DOCX generation test passed"
    rm test_document.docx
else
    echo "❌ DOCX generation test failed"
fi

echo ""
echo "🎉 API testing complete!"
EOF

chmod +x test_api.sh

# Create a README for the deployment
print_status "Creating deployment README..."
cat > README_DEPLOYMENT.md << 'EOF'
# Markdown Render API - Deployment

This directory contains your deployed Markdown Render API.

## Quick Start

1. **Copy your API file**:
   ```bash
   cp /path/to/your/pdf_docx_api.py .
   ```

2. **Start the API**:
   ```bash
   ./start_api.sh
   ```

3. **Test the API**:
   ```bash
   ./test_api.sh
   ```

## Service Management

- **Enable service**: `sudo systemctl enable markdown-api`
- **Start service**: `sudo systemctl start markdown-api`
- **Stop service**: `sudo systemctl stop markdown-api`
- **Check status**: `sudo systemctl status markdown-api`
- **View logs**: `sudo journalctl -u markdown-api -f`

## Health Monitoring

Run the health check script:
```bash
./health_check.sh
```

## API Endpoints

- **Health**: http://localhost:8000/health
- **Documentation**: http://localhost:8000/docs
- **PDF Generation**: POST http://localhost:8000/render/pdf
- **DOCX Generation**: POST http://localhost:8000/render/docx

## Troubleshooting

- Check logs: `sudo journalctl -u markdown-api -f`
- Test manually: `./test_api.sh`
- Restart service: `sudo systemctl restart markdown-api`
EOF

print_status "Deployment setup complete! 🎉"
echo ""
echo "📋 Next steps:"
echo "1. Copy your pdf_docx_api.py file to: $PROJECT_DIR/"
echo "2. Start the API: cd $PROJECT_DIR && ./start_api.sh"
echo "3. Test the API: ./test_api.sh"
echo "4. Enable service: sudo systemctl enable markdown-api"
echo ""
echo "📖 For detailed documentation, see: LINUX_DEPLOYMENT_GUIDE.md"
echo ""
echo "🌐 Once running, your API will be available at: http://0.0.0.0:8000"
echo "📚 API documentation: http://0.0.0.0:8000/docs"
echo ""
print_status "Deployment script completed successfully! 🚀"
