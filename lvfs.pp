$venvpath = '/usr/lib/lvfs/env36'
if $use_letsencrypt {
  $nginx_letsencrypt = "
 only allow http:// URIs
if (\$scheme != \"https\") {
    return 301 https://\$server_name\$request_uri;
}

 support SSL using Let's Encrypt
listen       443 ssl;
ssl_certificate /etc/letsencrypt/live/localhost/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/localhost/privkey.pem;
include /etc/letsencrypt/options-ssl-nginx.conf;
ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
location /.well-known/ {
    alias /var/www/.well-known/;
}"
} else {
    $nginx_letsencrypt = ''
}
if $dbhost == 'localhost' {
    $dbsocket = '&unix_socket=/var/lib/mysql/mysql.sock'
    # set up the database
    package { 'mariadb-server':
      ensure => installed,
    }
    package { 'mariadb':
      ensure => installed,
    }
    file { '/etc/my.cnf.d/00-lvfs.cnf':
        ensure  => 'file',
        content => "# Managed by Puppet, DO NOT EDIT
    [mysqld]
    skip-networking
    max_allowed_packet=60M
    wait_timeout = 6000000
    skip-name-resolve
    max_connect_errors = 1000
    ",
        require => Package['mariadb-server'],
    }
    service { 'mariadb':
        ensure  => 'running',
        enable  => true,
        require => Package['mariadb-server'],
    }

} else {
    $dbsocket = ''
    package { 'mariadb':
      ensure => installed,
    }
}


file { '/var/www':
    ensure   => 'directory',
}
file { '/var/www/lvfs':
    ensure  => 'directory',
    owner   => 'uwsgi',
    group   => 'uwsgi',
    require => [ File['/var/www'], Package['uwsgi'] ],
}
vcsrepo { '/var/www/lvfs/admin':
    ensure   => latest,
    provider => git,
    revision => $lvfs_revision,
    source   => 'https://github.com/hughsie/lvfs-website.git',
    user     => 'uwsgi',
    group    => 'uwsgi',
    require  => [ File['/var/www/lvfs'], Package['uwsgi']],
}
file { '/var/www/lvfs/admin/deleted':
    ensure  => 'directory',
    owner   => 'uwsgi',
    group   => 'uwsgi',
    require => [ Vcsrepo['/var/www/lvfs/admin'], Package['uwsgi'] ],
}
file { '/var/www/lvfs/admin/hwinfo':
    ensure  => 'directory',
    owner   => 'uwsgi',
    group   => 'uwsgi',
    require => [ Vcsrepo['/var/www/lvfs/admin'], Package['uwsgi'] ],
}
file { '/var/www/lvfs/downloads':
    ensure  => 'directory',
    owner   => 'uwsgi',
    group   => 'uwsgi',
    require => [ File['/var/www/lvfs'], Package['uwsgi'] ],
}
file { '/var/www/lvfs/backup':
    ensure  => 'directory',
    owner   => 'uwsgi',
    group   => 'uwsgi',
    require => [ File['/var/www/lvfs'], Package['uwsgi'] ],
}
file { '/var/www/lvfs/admin/app/custom.cfg':
    ensure  => 'file',
    owner   => 'uwsgi',
    group   => 'uwsgi',
    content => "# Managed by Puppet, DO NOT EDIT
import os
DEBUG = False
PROPAGATE_EXCEPTIONS = True
SECRET_KEY = '${lvfs_secret_key}'
SECRET_PASSWORD_SALT = '${secret_password_salt}'
SECRET_ADDR_SALT = '${secret_addr_salt}'
SECRET_VENDOR_SALT = '${secret_vendor_salt}'
HOST_NAME = 'localhost'
APP_NAME = 'lvfs'
IP = '${server_ip}'
PORT = 80
DOWNLOAD_DIR = '/var/www/lvfs/downloads'
UPLOAD_DIR = '/var/www/lvfs/admin/uploads'
RESTORE_DIR = '/var/www/lvfs/admin/deleted'
HWINFO_DIR = '/var/www/lvfs/admin/hwinfo'
KEYRING_DIR = '/var/www/lvfs/.gnupg'
SQLALCHEMY_DATABASE_URI = 'mysql+pymysql://${dbusername}:${dbpassword}@${dbhost}/${dbname}?charset=utf8mb4${dbsocket}'
SQLALCHEMY_TRACK_MODIFICATIONS = False
MYSQL_DATABASE_CHARSET = 'utf8mb4'
SESSION_COOKIE_SECURE = ${using_ssl}
REMEMBER_COOKIE_SECURE = ${using_ssl}
MAIL_SERVER = '${mail_server}'
MAIL_PORT = '${mail_port}'
MAIL_USE_TLS = True
MAIL_USE_SSL = False
MAIL_USERNAME = '${mail_username}'
MAIL_PASSWORD = '${mail_password}'
MAIL_DEFAULT_SENDER = ('LVFS Admin Team', '${mail_sender}')
",
    require => [ File['/var/www/lvfs'], Package['uwsgi'], Vcsrepo['/var/www/lvfs/admin'] ],
}

yumrepo { 'hughes-lvfs-website':
    baseurl             => 'https://copr-be.cloud.fedoraproject.org/results/rhughes/lvfs-website/epel-7-$basearch/',
    descr               => 'Copr repo for lvfs-website owned by rhughes',
    gpgkey              => 'https://copr-be.cloud.fedoraproject.org/results/rhughes/lvfs-website/pubkey.gpg',
    gpgcheck            => 1,
    repo_gpgcheck       => 0,
    enabled             => 1,
    skip_if_unavailable => 1,
}

# python deps are installed using requirements.txt where possible
package { 'libappstream-glib':
    ensure  => installed,
    require => Yumrepo['hughes-lvfs-website'],
}
package { 'libgcab1':
    ensure  => installed,
    require => Yumrepo['hughes-lvfs-website'],
}
package { 'bsdtar':
    ensure => installed,
}
package { 'git':
    ensure => installed,
}
package { 'python36-psutil':
    ensure => installed,
}
package { 'python36-pip':
    ensure => installed,
}
package { 'python36-virtualenv':
    ensure => installed,
}
package { 'mariadb-devel':
    ensure => installed,
}
package { 'cairo-gobject-devel':
    ensure => installed,
}
package { 'gobject-introspection-devel':
    ensure => installed,
}
package { 'GeoIP-devel':
    ensure => installed,
}

exec { 'virtualenv_create':
    command => "/usr/bin/virtualenv-3.6 ${venvpath}",
    unless  => "/bin/test -d  ${venvpath}",
    require => [ Package['python36-virtualenv'] ],
    notify  => Exec['pip_requirements_install'],
}
exec { 'pip_requirements_install':
    command     => "${venvpath}/bin/pip3 install -r /var/www/lvfs/admin/requirements.txt",
    path        => '/usr/bin',
    refreshonly => true,
    require     => [ Vcsrepo['/var/www/lvfs/admin'], Package['python36-pip'], Exec['virtualenv_create'] ],
}
exec { 'flask_db_migrate':
    command     => "${venvpath}/bin/flask db migrate",
    cwd         => '/var/www/lvfs/admin',
    refreshonly => true,
    # lint:ignore:140chars
    require     => [ Vcsrepo['/var/www/lvfs/admin'], Package['python36-pip'], Exec['virtualenv_create'], File['/var/www/lvfs/admin/app/custom.cfg'] ],
    # lint:endignore
    subscribe   =>  Vcsrepo['/var/www/lvfs/admin'],
}

exec { 'flask_db_upgrade':
    command     => "${venvpath}/bin/flask db upgrade",
    cwd         => '/var/www/lvfs/admin',
    refreshonly => true,
    # lint:ignore:140chars
    require     => [ Vcsrepo['/var/www/lvfs/admin'], Package['python36-pip'], Exec['virtualenv_create'], File['/var/www/lvfs/admin/app/custom.cfg'] ],
    # lint:endignore
    subscribe   =>  Exec['flask_db_migrate'],
}

# required for the PKCS#7 support
package { 'gnutls-utils':
    ensure => installed,
}


# lint:ignore:140chars
cron { 'purgedelete':
    command     => "cd /var/www/lvfs/admin; ${venvpath}/bin/python3 /var/www/lvfs/admin/cron.py purgedelete >> /var/log/uwsgi/lvfs-firmware.log 2>&1",
    user        => 'uwsgi',
    environment => 'LVFS_APP_SETTINGS=/var/www/lvfs/admin/app/custom.cfg',
    minute      => 0,
    hour        => 0,
    require     => Vcsrepo['/var/www/lvfs/admin'],
}
cron { 'stats':
    command     => "cd /var/www/lvfs/admin; ${venvpath}/bin/python3 /var/www/lvfs/admin/cron.py stats >> /var/log/uwsgi/lvfs-stats.log 2>&1",
    user        => 'uwsgi',
    environment => 'LVFS_APP_SETTINGS=/var/www/lvfs/admin/app/custom.cfg',
    minute      => 0,
    hour        => 2,
    require     => Vcsrepo['/var/www/lvfs/admin'],
}
cron { 'sign-firmware':
    command     => "cd /var/www/lvfs/admin; ${venvpath}/bin/python3 /var/www/lvfs/admin/cron.py firmware >> /var/log/uwsgi/lvfs-firmware.log 2>&1",
    user        => 'uwsgi',
    environment => 'LVFS_APP_SETTINGS=/var/www/lvfs/admin/app/custom.cfg',
    hour        => '*',
    minute      => '*/5',
    require     => Vcsrepo['/var/www/lvfs/admin'],
}
cron { 'fwchecks':
    command     => "cd /var/www/lvfs/admin; ${venvpath}/bin/python3 /var/www/lvfs/admin/cron.py fwchecks >> /var/log/uwsgi/lvfs-firmware.log 2>&1",
    user        => 'uwsgi',
    environment => 'LVFS_APP_SETTINGS=/var/www/lvfs/admin/app/custom.cfg',
    hour        => '*',
    minute      => '*/5',
    require     => Vcsrepo['/var/www/lvfs/admin'],
}
cron { 'sign-metadata':
    command     => "cd /var/www/lvfs/admin; ${venvpath}/bin/python3 /var/www/lvfs/admin/cron.py firmware metadata >> /var/log/uwsgi/lvfs-metadata.log 2>&1",
    user        => 'uwsgi',
    environment => 'LVFS_APP_SETTINGS=/var/www/lvfs/admin/app/custom.cfg',
    hour        => '*',
    minute      => '*/30',
    require     => Vcsrepo['/var/www/lvfs/admin'],
}
cron { 'mysqldump':
    command => "/usr/bin/mysqldump -h ${dbhost} -u ${dbuser} -p ${dbpassword} --single-transaction --default-character-set=utf8mb4 --ignore-table=lvfs.settings ${dbname} | gzip > /var/www/lvfs/backup/lvfs_$( date +\"\\%Y\\%m\\%d\" ).sql.gz",
    user    => 'root',
    hour    => 0,
    minute  => 0,
    require => Package['mariadb'],
}
# lint:endignore
# use uWSGI
package { 'uwsgi-plugin-python36':
    ensure => installed,
}
package { 'uwsgi':
    ensure => installed,
}
file { '/var/log/uwsgi':
    ensure  => 'directory',
    owner   => 'uwsgi',
    group   => 'uwsgi',
    require => Package['uwsgi'],
}
file { '/etc/tmpfiles.d/uwsgi.conf':
    ensure  => 'file',
    content => 'D /run/uwsgi 0770 uwsgi uwsgi -',
    require => Package['uwsgi'],
}
file { '/run/uwsgi':
    ensure  => 'directory',
    owner   => 'uwsgi',
    group   => 'uwsgi',
    mode    =>  '0770',
    require => Package['uwsgi'],
}
file { '/etc/uwsgi.d/lvfs.ini':
    ensure  => 'file',
    owner   => 'uwsgi',
    group   => 'uwsgi',
    content => "# Managed by Puppet, DO NOT EDIT
[uwsgi]
chdir = /var/www/lvfs/admin
virtualenv = ${venvpath}
module = app:app
plugins = python36
uid = uwsgi
gid = uwsgi
socket = /run/uwsgi/%n.socket
chmod-socket = 660
logto = /var/log/uwsgi/%n.log
stats = 127.0.0.1:9191
processes = 4
buffer-size = 65536
enable-threads = true
harakiri = 180
",
    require => Package['uwsgi'],
}
service { 'uwsgi':
    ensure    => 'running',
    enable    => true,
    require   => [ Package['uwsgi'], File['/etc/uwsgi.d/lvfs.ini'],File['/run/uwsgi'] ],
    subscribe => File['/var/www/lvfs/admin/app/custom.cfg'],
}

exec { 'nginx-uwsgi-membership':
    unless  => '/bin/grep -q "uwsgi\\S*nginx" /etc/group',
    command => '/sbin/usermod -aG uwsgi nginx',
    require => Package['uwsgi'],
}

# start nginx load balancer
package { 'nginx':
    ensure => installed,
}
file { '/etc/nginx/nginx.conf':
    ensure  => 'file',
    content => "# Managed by Puppet, DO NOT EDIT
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] \"\$request\" '
                      '\$status \$body_bytes_sent \"\$http_referer\" '
                      '\"\$http_user_agent\" \"\$http_x_forwarded_for\"';

    access_log  /var/log/nginx/access.log  main;

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 2048;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    include /etc/nginx/conf.d/*.conf;

    server {
        listen       80 default_server;
        listen       [::]:80 default_server;

        server_name  localhost;
        root         /usr/share/nginx/html;
        client_max_body_size 80M;

        ${nginx_letsencrypt}

        # Prevent browsers from incorrectly detecting non-scripts as scripts
        # https://wiki.mozilla.org/Security/Guidelines/Web_Security#X-Content-Type-Options
        add_header X-Content-Type-Options nosniff;

        # Prevents external sites from embedding this site in an iframe
        # https://wiki.mozilla.org/Security/Guidelines/Web_Security#X-Frame-Options
        add_header X-Frame-Options DENY;

        # Block pages from loading when they detect reflected XSS attacks
        # https://wiki.mozilla.org/Security/Guidelines/Web_Security#X-XSS-Protection
        add_header X-XSS-Protection \"1; mode=block\";

        # Never send the Referer header to preserve the users privacy
        # https://wiki.mozilla.org/Security/Guidelines/Web_Security#Referrer_Policy
        add_header Referrer-Policy no-referrer;

        # Block site from being framed with X-Frame-Options
        # https://wiki.mozilla.org/Security/Guidelines/Web_Security#X-Frame-Options
        add_header X-Frame-Options DENY;

        # Only connect to this site via HTTPS
        # https://wiki.mozilla.org/Security/Guidelines/Web_Security#HTTP_Strict_Transport_Security
        add_header Strict-Transport-Security \"max-age=63072000; includeSubDomains; preload\";

        # Block pages from loading when they detect reflected XSS attacks
        # https://wiki.mozilla.org/Security/Guidelines/Web_Security#Content_Security_Policy
        add_header Content-Security-Policy \"default-src 'none'; script-src 'self' 'unsafe-inline' 'unsafe-eval' https://stackpath.bootstrapcdn.com https://code.jquery.com https://cdnjs.cloudflare.com; img-src 'self' data:; style-src 'self' 'unsafe-inline' https://stackpath.bootstrapcdn.com https://fonts.googleapis.com https://use.fontawesome.com; font-src 'self' https://fonts.gstatic.com https://use.fontawesome.com; frame-ancestors 'none'\";

        # Load configuration files for the default server block.
        include /etc/nginx/default.d/*.conf;

        location /img/ {
            alias /var/www/lvfs/admin/app/static/img/;
        }
        location /uploads/ {
            alias /var/www/lvfs/admin/uploads/;
        }
        location /downloads/firmware.xml.gz {
            alias /var/www/lvfs/downloads/firmware.xml.gz;
            expires 20m;
        }
        location /downloads/firmware.xml.gz.asc {
            alias /var/www/lvfs/downloads/firmware.xml.gz.asc;
            expires 20m;
        }
        location / {
            uwsgi_read_timeout 180s;
            uwsgi_send_timeout 180s;
            uwsgi_pass unix:///run/uwsgi/lvfs.socket;
            include uwsgi_params;
        }

        error_page 404 /404.html;
            location = /40x.html {
        }

        error_page 500 502 503 504 /50x.html;
            location = /50x.html {
            alias /var/www/lvfs/admin/app/templates/50x.html;
        }
    }
}
",
    require => [ Package['nginx'], Vcsrepo['/var/www/lvfs/admin'] ],
}
service { 'nginx':
    ensure  => 'running',
    enable  => true,
    require => [ Package['nginx'], Service['uwsgi'] ],
}

# allow monitoring server
package { 'munin':
    ensure => installed,
}
package { 'munin-plugins-ruby':
    ensure => installed,
}
service { 'munin-node':
    ensure  => 'running',
    enable  => true,
    require => Package['munin'],
}
package { 'httpd-tools':
    ensure => installed,
}
exec { 'munin-htpasswd':
    command => "/usr/bin/htpasswd -cb /etc/munin/munin-htpasswd ${munin_username} ${munin_password}",
    unless  => '/usr/bin/test -s /etc/munin/munin-htpasswd',
    require => [ Package['munin'], Package['httpd-tools'] ],
}
file { '/etc/nginx/default.d/munin.conf':
    ensure  => 'file',
    content => '# Managed by Puppet, DO NOT EDIT
location /munin/static/ {
    alias /etc/munin/static/;
    expires modified +1w;
}

location /munin/ {
    auth_basic Restricted;
    auth_basic_user_file /etc/munin/munin-htpasswd;
    alias /var/www/html/munin/;
    expires modified +310s;
}
',
    require => Package['nginx'],
}

# antivirus
package { 'clamav-update':
    ensure => installed,
}
package { 'clamav':
    ensure => installed,
}
package { 'clamav-server-systemd':
    ensure => installed,
}
exec { 'uwsgi virusgroup membership':
    unless  => '/bin/getent group virusgroup|/bin/cut -d: -f4|/bin/grep -q uwsgi',
    command => '/usr/sbin/usermod -a -G virusgroup uwsgi',
    require => Package['uwsgi'],
}
file { '/etc/clamd.d/scan.conf':
    ensure  => 'file',
    content => "# Managed by Puppet, DO NOT EDIT
LogSyslog yes
LocalSocket /var/run/clamd.scan/clamd.sock
LocalSocketGroup virusgroup
FixStaleSocket yes
User clamscan
DetectPUA yes
DisableCertCheck yes
ScanSWF no
ScanMail no
ScanPartialMessages no
ScanArchive yes
MaxFileSize 100M
MaxEmbeddedPE 100M
",
    require => Package['clamav'],
}

exec { 'clamav_update':
    command     => '/bin/freshclam',
    refreshonly => true,
    subscribe   => Package['clamav-update'],
}

service { 'clamd@scan':
    ensure  => 'running',
    enable  => true,
    require => [ Package['clamav'], File['/etc/clamd.d/scan.conf'], Exec['clamav_update'] ],
}

# fixes permissions after a key has been imported
file { '/var/www/lvfs/.gnupg':
    ensure  => 'directory',
    owner   => 'uwsgi',
    group   => 'uwsgi',
    require => File['/var/www/lvfs'],
}
exec { 'gnupg-uwsgi-chown':
    command => '/bin/chown -R uwsgi:uwsgi /var/www/lvfs/.gnupg/',
    require => File['/var/www/lvfs/.gnupg'],
}
