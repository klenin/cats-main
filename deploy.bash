#!/usr/bin/env bash
# user, that executes this script must be in sudo group

CATS_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" # assume, that script is in a root dir of repo
DBD_FIREBIRD_VERSION=1.00

# PROXY USERS, PLEASE READ THIS
# If your network is behind proxy please uncomment and set following variables
#export http_proxy=host:port
#export https_proxy=$http_proxy
#export ftp_proxy=$http_proxy
#
# You also NEED to replace following line in /etc/sudoers:
# Defaults        env_reset
# With:
# Defaults env_keep="http_proxy https_proxy ftp_proxy"

# Group, apache running under
http_group=www-data

packages=(git firebird2.1-dev firebird2.1-classic build-essential libaspell-dev
	aspell-en aspell-ru apache2 libapache2-mod-perl2 libapreq2-3 libapreq2-dev
	apache2-threaded-dev libapache2-mod-perl2-dev libexpat1 libexpat1-dev libapache2-request-perl)

cpan_packages=(DBI Algorithm::Diff Text::Aspell SQL::Abstract Archive::Zip
    JSON::XS YAML::Syck Apache2::Request XML::Parser::Expat Template)

sudo apt-get -y install ${packages[@]}

formal_input='https://github.com/downloads/klenin/cats-main/FormalInput.tgz'
DBD_firebird="http://search.cpan.org/CPAN/authors/id/M/MA/MARIUZ/DBD-Firebird-$DBD_FIREBIRD_VERSION.tar.gz"

sudo -H sh -c 'wget -O - http://cpanmin.us | perl - --sudo App::cpanminus' # unsafe, but asks password once
cpanm -S ${cpan_packages[@]}
cd $CATS_ROOT
git submodule init
git submodule update

wget $formal_input -O fi.tgz
tar -xzvf fi.tgz
pushd FormalInput/
perl Makefile.PL
make
sudo make install
popd
rm fi.tgz
rm -rf FormalInput

wget $DBD_firebird
tar -zxvf DBD-Firebird-$DBD_FIREBIRD_VERSION.tar.gz
pushd DBD-Firebird-$DBD_FIREBIRD_VERSION/
perl Makefile.PL
make
sudo make install
popd
rm DBD-Firebird-$DBD_FIREBIRD_VERSION.tar.gz
rm -rf DBD-Firebird-$DBD_FIREBIRD_VERSION

APACHE_CONFIG=$(cat <<EOF
PerlSetEnv CATS_DIR ${CATS_ROOT}/cgi-bin/
<VirtualHost *:80>
	PerlRequire ${CATS_ROOT}/cgi-bin/CATS/Web/startup.pl
	<Directory "${CATS_ROOT}/cgi-bin/">
		Options -Indexes +FollowSymLinks
		DirectoryIndex main.pl
		LimitRequestBody 1048576
		AllowOverride all
		Order allow,deny
		Allow from all
		<Files "main.pl">
			# Apache 2.x / ModPerl 2.x specific
			PerlResponseHandler main
			PerlSendHeader On
			SetHandler perl-script
		</Files>
	</Directory>

	ExpiresActive On
	ExpiresDefault "access plus 5 seconds"
	ExpiresByType text/css "access plus 1 week"
	ExpiresByType application/javascript "access plus 1 week"
	ExpiresByType image/gif "access plus 1 week"
	ExpiresByType image/x-icon "access plus 1 week"

	Alias /cats/static/ "${CATS_ROOT}/static/"
	<Directory "${CATS_ROOT}/static">
		# Apache allows only absolute URL-path
		ErrorDocument 404 /cats/main.pl?f=static
		#Options FollowSymLinks
		AddDefaultCharset utf-8
	</Directory>

	Alias /cats/docs/ "${CATS_ROOT}/docs/"
	<Directory "${CATS_ROOT}/docs">
		AddDefaultCharset utf-8
	</Directory>

	Alias /cats/ev/ "${CATS_ROOT}/ev/"
	<Directory "${CATS_ROOT}/ev">
		AddDefaultCharset utf-8
	</Directory>

	<Directory "${CATS_ROOT}/docs/std/">
		AllowOverride Options=Indexes,MultiViews,ExecCGI FileInfo
	</Directory>

	<Directory "${CATS_ROOT}/images/std/">
		AllowOverride Options=Indexes,MultiViews,ExecCGI FileInfo
	</Directory>

	<Directory "${CATS_ROOT}/score/">
        AllowOverride Options=Indexes,MultiViews,ExecCGI FileInfo
        LimitRequestBody 1048576
		Options +ExecCGI
		AddHandler perl-script .pl
		PerlResponseHandler ModPerl::Registry
    </Directory>

    <Directory "${CATS_ROOT}/js/">
        AllowOverride Options=Indexes,MultiViews,ExecCGI FileInfo
    </Directory>

	Alias /cats/synh/ "${CATS_ROOT}/synhighlight/"
	Alias /cats/images/ "${CATS_ROOT}/images/"
	Alias /cats/score/ "${CATS_ROOT}/score/"
	Alias /cats/js/ "${CATS_ROOT}/js/"
	Alias /cats/ "${CATS_ROOT}/cgi-bin/"
</VirtualHost>
EOF
)

sudo sh -c "echo '$APACHE_CONFIG' > /etc/apache2/sites-available/000-cats.conf"
sudo ln -s /etc/apache2/sites-{available,enabled}/000-cats.conf
[[ -e /etc/apache2/sites-enabled/000-default ]] && sudo rm /etc/apache2/sites-enabled/000-default.conf
[[ -e /etc/apache2/mods-enabled/expires.load ]] || sudo ln -s /etc/apache2/mods-{available,enabled}/expires.load
[[ -e /etc/apache2/mods-enabled/apreq2.load ]] || sudo ln -s /etc/apache2/mods-{available,enabled}/apreq2.load

# generate docs
cd docs
ttree -f ttreerc
cd ..

# now adjust permissions
sudo chgrp -R ${http_group} cgi-bin static templates tt
chmod -R g+r cgi-bin
chmod g+rw static tt cgi-bin/download/{,att,img,pr} cgi-bin/rank_cache{,/r}

sudo service apache2 restart

CONNECT_NAME="Connect.pm"
CONNECT_ROOT="${CATS_ROOT}/cgi-bin/CATS"
CREATE_DB_NAME="create_db.sql"
CREATE_DB_ROOT="${CATS_ROOT}/sql/interbase"

CONNECT="$CONNECT_ROOT/$CONNECT_NAME"
cp "$CONNECT_ROOT/${CONNECT_NAME}.template" $CONNECT

CREATE_DB="$CREATE_DB_ROOT/$CREATE_DB_NAME"
cp "$CREATE_DB_ROOT/${CREATE_DB_NAME}.template" $CREATE_DB

echo -e "...\n...\n..."

answer=""
while [ "$answer" != "y" -a "$answer" != "n" ]; do
   echo -n "Do you want to do the automatic setup? "
   read answer
done

if [ "$answer" = "n" ]; then
   echo -e "Setup is done, you need to do following manualy:\n"
   echo -e " 1. Navigate to ${CONNECT_ROOT}/"
   echo -e " 2. Adjust your database connection settings in ${CONNECT_NAME}"
   echo -e " 3. Navigate to ${CREATE_DB_ROOT}/"
   echo -e " 4. Adjust your database connection settings in ${CREATE_DB_NAME} and create database\n"
   exit 0
fi

echo -n "path-to-your-database: " && read path_to_db
echo -n "your-host: " && read db_host
echo -n "your-db-username: "&& read db_user
echo -n "your-db-password: " && read db_pass

sed -i -e "s/<path-to-your-database>/$path_to_db/g" $CONNECT
sed -i -e "s/<your-host>/$db_host/g" $CONNECT
sed -i -e "s/<your-username>/$db_user/g" $CONNECT
sed -i -e "s/<your-password>/$db_pass/g" $CONNECT

sed -i -e "s/<path-to-your-database>/$path_to_db/g" $CREATE_DB
sed -i -e "s/<your-username>/$db_user/g" $CREATE_DB
sed -i -e "s/<your-password>/$db_pass/g" $CREATE_DB
