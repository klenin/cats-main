#!/usr/bin/env bash
# user, that executes this script must be in sudo group

CATS_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" # assume, that script is in a root dir of repo 

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

# Group, apache running with
http_group=www-data

packets=(git firebird2.1-dev firebird2.1-classic build-essential libaspell-dev
	aspell-en aspell-ru apache2 libapache2-mod-perl2 libapreq2 libapreq2-dev 
	apache2-threaded-dev libapache2-mod-perl2-dev libexpat1 libexpat1-dev)
cpan_packets=(DBI Algorithm::Diff Text::Aspell HTML::Template SQL::Abstract 
	Archive::Zip JSON::XS YAML::Syck Apache2::Request XML::Parser::Expat)

sudo apt-get -y install ${packets[@]}

formal_input='https://github.com/downloads/klenin/cats-main/FormalInput.tgz'
DBD_firebird='http://search.cpan.org/CPAN/authors/id/M/MA/MARIUZ/DBD-Firebird-0.60.tar.gz'

sudo -H sh -c 'wget -O - http://cpanmin.us | perl - --sudo App::cpanminus' # unsafe, but asks password once
cpanm -S ${cpan_packets[@]}
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
tar -zxvf DBD-Firebird-0.60.tar.gz
pushd DBD-Firebird-0.60/
perl Makefile.PL
make
sudo make install
popd
rm DBD-Firebird-0.60.tar.gz
rm -rf DBD-Firebird-0.60

APACHE_CONFIG=$(cat <<EOF
<VirtualHost *:80>
	#    PerlRequire /var/www/perllib/startup.perl
	PerlSetEnv CATS_DIR ${CATS_ROOT}/cgi-bin/
	<Directory "${CATS_ROOT}/cgi-bin/">
	    Options -Indexes +ExecCGI +FollowSymLinks
	    DirectoryIndex main.pl
	    LimitRequestBody 1048576
	    AllowOverride none
	    Order allow,deny         
	    Allow from all
	    <Files "main.pl">
	        # Apache 2.x / ModPerl 2.x specific
	        PerlHandler ModPerl::Registry
	        PerlSendHeader On
	        SetHandler perl-script
	    </Files>
	</Directory>

	ExpiresActive On
	ExpiresDefault "access plus 5 seconds"

	Alias /cats/static/ "${CATS_ROOT}/static/"
	<Directory "${CATS_ROOT}/static">
	    # Apache допускает только абсолютный URL-path
	    ErrorDocument 404 /cats/main.pl?f=static
	    #Options FollowSymLinks
	    AddDefaultCharset utf-8
	</Directory>

	Alias /cats/docs/ "${CATS_ROOT}/docs/"
	<Directory "${CATS_ROOT}/docs">
	    AddDefaultCharset KOI8-R
	</Directory>

	Alias /cats/ev/ "${CATS_ROOT}/ev/"
	<Directory "${CATS_ROOT}/ev">
	    AddDefaultCharset utf-8
	</Directory>

	Alias /cats/synh/ "${CATS_ROOT}/synhighlight/"
	Alias /cats/images/ "${CATS_ROOT}/images/"
	Alias /cats/ "${CATS_ROOT}/cgi-bin/"
</VirtualHost>
EOF
)

sudo sh -c "echo '$APACHE_CONFIG' > /etc/apache2/sites-available/000-cats"
sudo ln -s /etc/apache2/sites-{available,enabled}/000-cats
[[ -e /etc/apache2/sites-enabled/000-default ]] && sudo rm /etc/apache2/sites-enabled/000-default
[[ -e /etc/apache2/mods-enabled/expires.load ]] || sudo ln -s /etc/apache2/mods-{available,enabled}/expires.load
[[ -e /etc/apache2/mods-enabled/apreq.load ]] || sudo ln -s /etc/apache2/mods-{available,enabled}/apreq.load

# now adjust permissions
sudo chgrp -R ${http_group} cgi-bin static templates
chmod -R g+r cgi-bin
chmod g+rw static cgi-bin/download/{,att,img,pr} cgi-bin/rank_cache

sudo service apache2 restart

echo -e "...\n...\n...\nSetup is now complete, you need to do following manualy:\n\n"

echo -e "Please now navigate to ${CATS_ROOT}/cgi-bin/CATS/"
echo -e "copy Connect.pm.template into Connect.pm"
echo -e "and adjust your database connection settings"
