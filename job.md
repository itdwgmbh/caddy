name: Build Caddy with Plugins

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
  workflow_dispatch:
  schedule:
    # Run on the first day of each month at 00:00 UTC
    - cron: '0 0 1 * *'

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.get-version.outputs.version }}
      date: ${{ steps.get-date.outputs.date }}
      
    steps:
    - uses: actions/checkout@v4
    
    - name: Set up Go
      uses: actions/setup-go@v5
      with:
        go-version: 'stable'
        check-latest: true
    
    - name: Install xcaddy
      run: |
        go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
    
    - name: Build Caddy with plugins
      run: |
        xcaddy build \
          --with github.com/digilolnet/caddy-bunny-ip \
          --output ./caddy
          
    - name: Get current date
      id: get-date
      run: echo "date=$(date +'%Y-%m-%d')" >> $GITHUB_OUTPUT
    
    - name: Install FPM
      run: |
        sudo apt-get update
        sudo apt-get install -y ruby ruby-dev build-essential
        sudo gem install fpm
    
    - name: Create DEB package
      id: get-version
      run: |
        # Get Caddy version from the built binary
        CADDY_VERSION=$(./caddy version | grep -oP 'v\d+\.\d+\.\d+' | head -1)
        # Remove 'v' prefix if present
        VERSION="${CADDY_VERSION#v}"
        
        # Save version for later use
        echo "version=${VERSION}" >> $GITHUB_OUTPUT
        
        # Create directories for packaging
        mkdir -p ./deb/usr/bin
        mkdir -p ./deb/etc/caddy
        mkdir -p ./deb/etc/systemd/system
        mkdir -p ./deb/usr/share/doc/caddy
        mkdir -p ./deb/var/log/caddy
        
        # Copy binary and configuration
        cp ./caddy ./deb/usr/bin/
        cp ./Caddyfile ./deb/etc/caddy/
        
        # Build DEB package
        fpm -s dir -t deb \
          -n caddy \
          -v "${VERSION}" \
          --vendor "Caddy Web Server" \
          --maintainer "Your Name <your.email@example.com>" \
          --description "Caddy Web Server with plugins" \
          --url "https://caddyserver.com" \
          --license "Apache-2.0" \
          --depends "ca-certificates" \
          --deb-no-default-config-files \
          --deb-systemd ./caddy.service \
          --before-install ./scripts/preinst.sh \
          --after-install ./scripts/postinst.sh \
          --before-remove ./scripts/prerm.sh \
          --after-remove ./scripts/postrm.sh \
          -C ./deb \
          -p caddy.deb
    
    - name: Upload DEB package
      uses: actions/upload-artifact@v4
      with:
        name: caddy-custom
        path: caddy.deb
        retention-days: 30

  publish-pages:
    needs: build
    runs-on: ubuntu-latest
    # Only run on main branch pushes and scheduled runs
    if: github.ref == 'refs/heads/main' || github.ref == 'refs/heads/master' || github.event_name == 'schedule' || github.event_name == 'workflow_dispatch'
    permissions:
      contents: read
      pages: write
      id-token: write
    
    steps:
    - name: Checkout repository
      uses: actions/checkout@v4
    
    - name: Download built DEB package
      uses: actions/download-artifact@v4
      with:
        name: caddy-custom
        path: ./dist
    
    - name: Setup Pages
      uses: actions/configure-pages@v5
    
    - name: Create website content
      run: |
        mkdir -p _site
        
        # Version and date from build job
        VERSION="${{ needs.build.outputs.version }}"
        BUILD_DATE="${{ needs.build.outputs.date }}"
        DEB_FILE=./dist/caddy.deb
        DEB_FILENAME=caddy.deb
        
        # Copy DEB file to site directory
        cp "$DEB_FILE" _site/
        
        # Create index.html
        cat > _site/index.html << EOL
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Custom Caddy Build with Bunny IP Module</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, 'Open Sans', 'Helvetica Neue', sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
        }
        header {
            border-bottom: 1px solid #eee;
            margin-bottom: 20px;
            padding-bottom: 10px;
        }
        h1 {
            color: #00add8;
        }
        .build-info {
            background-color: #f5f5f5;
            padding: 15px;
            border-radius: 5px;
            margin-bottom: 20px;
        }
        .download-button {
            display: inline-block;
            background-color: #00add8;
            color: white;
            padding: 10px 20px;
            text-decoration: none;
            border-radius: 5px;
            font-weight: bold;
            margin-top: 10px;
        }
        .download-button:hover {
            background-color: #0092b8;
        }
        footer {
            margin-top: 40px;
            font-size: 0.8em;
            color: #666;
            border-top: 1px solid #eee;
            padding-top: 10px;
        }
        pre {
            background-color: #f1f1f1;
            padding: 10px;
            border-radius: 5px;
            overflow-x: auto;
        }
    </style>
</head>
<body>
    <header>
        <h1>Custom Caddy Build with Bunny IP Module</h1>
    </header>
    
    <main>
        <div class="build-info">
            <h2>Latest Build Information</h2>
            <p><strong>Version:</strong> Caddy $VERSION</p>
            <p><strong>Build Date:</strong> $BUILD_DATE</p>
            <p><strong>Custom Modules:</strong> github.com/digilolnet/caddy-bunny-ip</p>
            <p><strong>Configuration:</strong> ZeroSSL as ACME CA, Admin API, Metrics, JSON logging</p>
            
            <a href="$DEB_FILENAME" class="download-button">Download DEB Package</a>
        </div>
        
        <h2>Installation</h2>
        <p>To install the DEB package, use the following commands:</p>
        <pre>wget https://$(echo \${GITHUB_REPOSITORY_OWNER}.github.io/$(echo \${GITHUB_REPOSITORY#*/})/$DEB_FILENAME)
sudo dpkg -i $DEB_FILENAME
sudo apt-get install -f</pre>
        
        <h2>Features</h2>
        <ul>
            <li>Caddy web server with the Bunny IP module</li>
            <li>ZeroSSL configured as the only ACME CA provider</li>
            <li>Admin API enabled on 127.0.0.1:2019</li>
            <li>Metrics available on 127.0.0.1:2020 with host metrics enabled</li>
            <li>JSON logging to /var/log/caddy/</li>
            <li>Systemd service configuration</li>
        </ul>
        
        <h2>Default Configuration</h2>
        <p>The package comes with a default Caddyfile that includes:</p>
        <pre>{
  # Global options
  admin 127.0.0.1:2019
  
  # Use ZeroSSL as the only ACME CA
  acme_ca https://acme.zerossl.com/v2/DV90
  
  # Enable logging
  log {
    output file /var/log/caddy/access.log
    format json
  }
  
  # Enable metrics
  metrics 127.0.0.1:2020 {
    enable_host_metrics
  }
}

:80 {
  # Set this path to your site's directory
  root * /usr/share/caddy
  
  # Enable logging for this host
  log {
    output file /var/log/caddy/{host}.access.log
    format json
  }
  
  # Enable the static file server
  file_server
}</pre>
    </main>
    
    <footer>
        <p>This custom Caddy build is automatically updated on the first day of each month. Last updated: $BUILD_DATE</p>
    </footer>
</body>
</html>
EOL
    
    - name: Upload artifact
      uses: actions/upload-pages-artifact@v3
    
    - name: Deploy to GitHub Pages
      id: deployment
      uses: actions/deploy-pages@v4
