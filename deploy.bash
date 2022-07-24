#!/usr/bin/env bash
# user, that executes this script must be in sudo group

#parse command line
step="*"

while [[ $# -gt 1 ]]; do
	key=$1
	case $key in 
	-s|--step)
		step="$2"
		shift
	;;
	*)
		echo 'Unknown option: '
		tail -1 $key
		exit
	;;
	esac
	shift
done
if [[ -n $1 ]]; then
	echo "Last option not have argument: "
	tail -1 $1
	exit
fi

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

# Group, apache running under
http_group=www-data

FB_DEV_VERSION=`sudo apt-cache pkgnames | grep firebird-dev`
FB_DEV_VERSION=`sudo apt-cache show firebird-dev | grep Version`
[[ $FB_DEV_VERSION =~ ([0-9]+\.[0-9]+) ]]
FB_DEV_VERSION=${BASH_REMATCH[1]}
FB_DEF_OP_MODE='superclassic'
packages=(firebird-dev)

# The firebird-dev package may contain different verisons of Firebird.
# It depends on platform you're using.
# Packages firebird2.*-(classic|super|superclassic) are mutually exclusive.
# Firebird 3.0 and higher allows to switch Operation Mode in the
# /etc/firebird/3.*/firebird.conf

echo "1. Install apt packages... "
if [[ $step =~ (^|,)1(,|$)  || $step == "*" ]]; then
	if [[ FB_DEV_VERSION ]]
	then
		if [[ `echo "$FB_DEV_VERSION < 3.0" | bc` -eq 1 ]]; then
			read -e -p "Firebird Operation Mode (classic, super, superclassic): " -i $FB_DEF_OP_MODE $FB_DEF_OP_MODE
			FB_PACKAGE=firebird${FB_DEV_VERSION}-${FB_DEF_OP_MODE}
		else
			FB_PACKAGE=firebird${FB_DEV_VERSION}-server
		fi
		packages+=($FB_PACKAGE)
	else
		echo "Can't find a proper firebird-dev package"
	fi

	packages+=(git unzip wget build-essential libaspell-dev
		aspell-en aspell-ru apache2 libapache2-mod-perl2 libapreq2-3 libapreq2-dev
		libapache2-mod-perl2-dev libexpat1 libexpat1-dev libapache2-request-perl cpanminus)
	sudo apt-get -y install ${packages[@]}
	sudo dpkg-reconfigure $FB_PACKAGE # In some cases default dialog just doesn't configure SYSDBA user
	echo "ok"
else
	echo "skip"
fi

echo "2. Install cpan packages... "
if [[ $step =~ (^|,)2(,|$) || $step == "*" ]]; then
	cpan_packages=(
		Module::Install
		DBI
		DBD::Firebird

		Algorithm::Diff
		Apache2::Request
		Archive::Zip
		Authen::Passphrase
		File::Copy::Recursive
		JSON::XS
		SQL::Abstract
		Template
		Test::Exception
		Text::Aspell
		Text::CSV
		Text::MultiMarkdown
		XML::Parser::Expat
		YAML::Syck
	)
	sudo cpanm -S ${cpan_packages[@]}
	echo "ok"
else
	echo "skip"
fi

echo "3. Init and update submodules... "
if [[ $step =~ (^|,)3(,|$) || $step == "*" ]]; then
	git submodule init
	git submodule update
	echo "ok"
else
	echo "skip"
fi


echo "4. Install formal input... "
if [[ $step =~ (^|,)4(,|$) || $step == "*" ]]; then
	formal_input='https://github.com/downloads/klenin/cats-main/FormalInput.tgz'
	wget $formal_input -O fi.tgz
	tar -xzvf fi.tgz
	pushd FormalInput/
	perl Makefile.PL
	make
	sudo make install
	popd
	rm fi.tgz
	rm -rf FormalInput
	echo "ok"
else
	echo "skip"
fi

echo "5. Generating docs... "
if [[ $step =~ (^|,)5(,|$) || $step == "*" ]]; then
	cd docs/tt
	ttree -f ttreerc
	cd $CATS_ROOT
	echo "ok"
else
	echo "skip"
fi

echo "6. Configure Apache... "
if [[ $step =~ (^|,)6(,|$) || $step == "*" ]]; then
APACHE_CONFIG=$(cat <<EOF
PerlSetEnv CATS_DIR ${CATS_ROOT}/cgi-bin/
<VirtualHost *:80>
	PerlRequire ${CATS_ROOT}/cgi-bin/CATS/Web/startup.pl
	<Directory "${CATS_ROOT}/cgi-bin/">
		Options -Indexes
		LimitRequestBody 1048576
		Require all granted
		PerlSendHeader On
		SetHandler perl-script
		PerlResponseHandler main
	</Directory>
	ExpiresActive On
	ExpiresDefault "access plus 5 seconds"
	ExpiresByType text/css "access plus 1 week"
	ExpiresByType application/javascript "access plus 1 week"
	ExpiresByType image/gif "access plus 1 week"
	ExpiresByType image/png "access plus 1 week"
	ExpiresByType image/x-icon "access plus 1 week"

	Alias /cats/static/css/ "${CATS_ROOT}/css/"
	Alias /cats/static/ "${CATS_ROOT}/static/"
	<Directory "${CATS_ROOT}/static">
		# Apache allows only absolute URL-path
		ErrorDocument 404 /cats/?f=static
		#Options FollowSymLinks
		AddDefaultCharset utf-8
		Require all granted
	</Directory>

	Alias /cats/download/ "${CATS_ROOT}/download/"
	<Directory "${CATS_ROOT}/download">
		Options -Indexes
		Require all granted
		AddCharset utf-8 .txt
	</Directory>

	Alias /cats/docs/ "${CATS_ROOT}/docs/"
	<Directory "${CATS_ROOT}/docs">
		AddDefaultCharset utf-8
		Require all granted
	</Directory>

	Alias /cats/ev/ "${CATS_ROOT}/ev/"
	<Directory "${CATS_ROOT}/ev">
		AddDefaultCharset utf-8
		Require all granted
	</Directory>

	Alias /cats/css/ "${CATS_ROOT}/css/"
	<Directory "${CATS_ROOT}/css/">
		AllowOverride Options=Indexes,MultiViews,ExecCGI FileInfo
		Require all granted
	</Directory>

	Alias /cats/images/ "${CATS_ROOT}/images/"
	<Directory "${CATS_ROOT}/images/">
		AllowOverride Options=Indexes,MultiViews,ExecCGI FileInfo
		Require all granted
	</Directory>   

	Alias /cats/js/ "${CATS_ROOT}/js/"
	<Directory "${CATS_ROOT}/js/">
		AllowOverride Options=Indexes,MultiViews,ExecCGI FileInfo
		Require all granted
	</Directory>

	Alias /cats/ "${CATS_ROOT}/cgi-bin/"
</VirtualHost>
EOF
)
	
	sudo sh -c "echo '$APACHE_CONFIG' > /etc/apache2/sites-available/000-cats.conf"
	sudo a2ensite 000-cats
	sudo a2dissite 000-default
	sudo a2enmod expires
	sudo a2enmod apreq2
	# Adjust permissions.
	sudo chgrp -R ${http_group} cgi-bin css download images static tt
	chmod -R g+r cgi-bin
	chmod g+rw static tt download/{,att,f,img,pr,vis} cgi-bin/rank_cache{,/r} cgi-bin/repos
	sudo service apache2 reload
	sudo service apache2 restart
	echo "ok"
else
	echo "skip"
fi

echo "7. Download JS... "
if [[ $step =~ (^|,)7(,|$) || $step == "*" ]]; then
    perl -e 'install_js.pl --install=all'
	cd $CATS_ROOT
	echo "ok"
else
	echo "skip"
fi

echo "8. Configure and init cats database... "
if [[ ($step =~ (^|,)8(,|$) || $step == "*") && $FB_DEV_VERSION ]]; then
	firebird="1"
	dbms=""
	while [ "$dbms" != "1" -a "$dbms" != "2" ]; do
		echo -e "Choose DBMS:\n  1. Firebird\n  2. Postgres"
		read dbms
	done

	CONFIG_NAME="Config.pm"
	CONFIG_ROOT="${CATS_ROOT}/cgi-bin/cats-problem/CATS"
	CREATE_DB_NAME="create_db.sql"
	CREATE_DB_ROOT="${CATS_ROOT}/sql/"
	if [[ "$dbms" = "$firebird" ]]; then
		CREATE_DB_ROOT+="interbase"
	else
		sudo apt-get -y install "postgresql" "libpq-dev"
		sudo service postgresql restart
		sudo cpanm -S "DBD::Pg"
		CREATE_DB_ROOT+="postgres"
	fi

	echo -e "...\n...\n..."

	answer=""
	while [ "$answer" != "y" -a "$answer" != "n" ]; do
	   echo -n "Do you want to do the automatic setup? "
	   read answer
	done

	if [ "$answer" = "n" ]; then
	   echo -e "Setup is done, you need to do following manualy:\n"
	   echo -e " 1. Navigate to ${CONFIG_ROOT}/"
	   echo -e " 2. Adjust your database connection settings in ${CONFIG_NAME}"
	   echo -e " 3. Navigate to ${CREATE_DB_ROOT}/"
	   echo -e " 4. Adjust your database connection settings in ${CREATE_DB_NAME} and create database\n"
	   exit 0
	fi

	def_db_host="localhost"
	read -e -p "Host: " -i $def_db_host db_host
	read -e -p "Username: " db_user
	read -e -p "Password: " db_pass

	if [[ "$dbms" = "$firebird" ]]; then
		def_path_to_db="$HOME/.cats/cats.fdb"
		read -e -p "Path to database: " -i $def_path_to_db path_to_db

		FB_ALIASES="/etc/firebird/${FB_DEV_VERSION}/"
		# aliases.conf is replaced by databases.conf in firebird 3.x
		FB_ALIASES=$FB_ALIASES$([ `echo "$FB_DEV_VERSION < 3.0" | bc` -eq 1 ] && 
							       echo "aliases.conf" || echo "databases.conf")
		
		alias="cats = $path_to_db"
		has_alias=$(sudo cat $FB_ALIASES | grep -c "$alias")
		if [ $has_alias -eq 0 ]; then
			sudo sh -c "echo 'cats = $path_to_db' >> $FB_ALIASES"
		fi

		if [[ "$path_to_db" = "$def_path_to_db" ]]; then
			mkdir "$HOME/.cats"
		fi
		sudo chown firebird.firebird $(dirname "$path_to_db")

		perl -I "$CATS_ROOT/cgi-bin" -MCATS::Deploy -e \
			"CATS::Deploy::create_db interbase, cats, '$db_user', '$db_pass', init_config => 1,
				host => '$db_host', quiet => 1"
	else
		perl -I "$CATS_ROOT/cgi-bin" -MCATS::Deploy -e \
			"CATS::Deploy::create_db postgres, cats, '$db_user', '$db_pass', pg_auth_type => peer,
				init_config => 1, host => '$db_host', quiet => 1"
	fi
	echo "ok"
else
	echo "skip"
fi
