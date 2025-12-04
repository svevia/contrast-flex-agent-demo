FROM ubuntu:24.04

# Set timezone to avoid interactive prompts during package installation
RUN ln -fs /usr/share/zoneinfo/Etc/UTC /etc/localtime && \
    echo "Etc/UTC" > /etc/timezone

# Update package lists and install basic utilities
RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    apt-get install -y \
        curl \
        wget \
        vim \
        nano \
        git \
        build-essential \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        sudo \
        net-tools \
        iputils-ping \
        telnet \
        unzip \
        zip \
        jq \
        htop \
        tree \
        less \
    && rm -rf /var/lib/apt/lists/*


RUN DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y openjdk-11-jdk maven && \
    rm -rf /var/lib/apt/lists/* && \
    java --version

# Install Python and pip.
RUN DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y software-properties-common && \
    add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y python3.9-dev python3.9-venv python3-pip jq && \
    rm -rf /var/lib/apt/lists/* && \
    echo "alias python='python3.9'" >> ~/.bashrc && \
    echo "alias pip='python3.9 -m pip'" >> ~/.bashrc

# Install Python packages using virtual environment
RUN python3.9 -m venv /opt/flask-env && \
    /opt/flask-env/bin/pip install flask && \
    echo 'export PATH="/opt/flask-env/bin:$PATH"' >> ~/.bashrc

# Install .NET Core SDK.
RUN curl https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb -o packages-microsoft-prod.deb && \
    dpkg -i packages-microsoft-prod.deb && \
    rm packages-microsoft-prod.deb && \
    apt-get update && \
    apt-get install -y dotnet-sdk-8.0

# Install Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_22.x -o nodesource_setup.sh && \
    bash nodesource_setup.sh && \
    apt-get install -y nodejs && \
    rm nodesource_setup.sh

# Install PHP 8.4 and Apache
RUN DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    add-apt-repository ppa:ondrej/php -y && \
    apt-get update && \
    apt-get install -y \
        apache2 \
        php8.4 \
        php8.4-cli \
        php8.4-common \
        php8.4-mysql \
        php8.4-xml \
        php8.4-curl \
        php8.4-gd \
        php8.4-mbstring \
        php8.4-zip \
        php8.4-bcmath \
        php8.4-intl \
        php8.4-sqlite3 \
        php8.4-opcache \
        libapache2-mod-php8.4 \
        sqlite3 \
    && rm -rf /var/lib/apt/lists/* && \
    php --version

# Configure Apache
RUN a2enmod rewrite && \
    a2enmod php8.4 && \
    phpenmod pdo pdo_sqlite && \
    echo "extension=pdo.so" >> /etc/php/8.4/cli/php.ini && \
    echo "extension=pdo_sqlite.so" >> /etc/php/8.4/cli/php.ini && \
    echo "extension=dom.so" >> /etc/php/8.4/cli/php.ini && \
    echo "extension=pdo.so" >> /etc/php/8.4/apache2/php.ini && \
    echo "extension=pdo_sqlite.so" >> /etc/php/8.4/apache2/php.ini && \
    echo "extension=dom.so" >> /etc/php/8.4/apache2/php.ini && \
    echo "ServerName localhost" >> /etc/apache2/apache2.conf

# Install Composer for PHP package management
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer && \
    composer --version


# Create demos directory and set as working directory
ADD DEMO /demos
WORKDIR /demos

RUN chmod +x /demos/*.sh && /demos/build-demos.sh

# Set execute permissions on scripts when copied to container
# This ensures scripts work regardless of host OS permissions
RUN echo '#!/bin/bash' > /usr/local/bin/fix-permissions.sh && \
    echo 'chmod +x /demos/*.sh 2>/dev/null || true' >> /usr/local/bin/fix-permissions.sh && \
    echo 'chmod +x /demos/demo-control.sh 2>/dev/null || true' >> /usr/local/bin/fix-permissions.sh && \
    chmod +x /usr/local/bin/fix-permissions.sh

# Keep container running
CMD ["/bin/bash", "-c", "/usr/local/bin/fix-permissions.sh && tail -f /dev/null"]
