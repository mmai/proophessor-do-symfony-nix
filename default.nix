with import <nixpkgs> { };

let
  cfg =
    if builtins.pathExists ./nixfiles/config.nix
    then import ./nixfiles/config.nix 
    else {  # default configuration
      nginxPort = "8080";
      mysqlPort = "3307";
      mysqlPassword = "admin";
    };

  rootDir   = toString ./.;
  nginxDir  = "${rootDir}/nixfiles/nginx";
  phpDir    = "${rootDir}/nixfiles/php";
  mysqlDir  = "${rootDir}/nixfiles/mysql";

  mysqlConf     = (import ./nixfiles/mysql/mysql.conf.nix) {inherit pkgs mysqlDir; mysqlPort = cfg.mysqlPort; };
  phpConf       = (import ./nixfiles/php/phpfpm-nginx.conf.nix) {inherit pkgs phpDir ;};
  phpIni        = (import ./nixfiles/php/phpini.nix) {inherit pkgs ;};
  nginxConf     = (import ./nixfiles/nginx/nginx.conf.nix) {inherit pkgs nginxDir rootDir phpDir; nginxPort = cfg.nginxPort; };
in

stdenv.mkDerivation rec {
  name = "mywebapp-${version}";
  version = "0.1.0";
  buildInputs = (with pkgs; [ php phpPackages.psysh phpPackages.xdebug phpPackages.composer nginx mysql57 ]); 

  shellHook = ''
    alias php="${pkgs.php}/bin/php -c ${phpIni}"
    function startServices {
      if test -f ${nginxDir}/logs/nginx.pid && ps -p $(cat ${nginxDir}/logs/nginx.pid) > /dev/null; then
        echo "NGINX already started"
      else
        echo "==============   Starting nginx..."
        ${pkgs.nginx}/bin/nginx -p ${nginxDir}/tmp  -c ${nginxConf}
      fi

      if test -f ${phpDir}/tmp/php-fpm.pid && ps -p $(cat ${phpDir}/tmp/php-fpm.pid) > /dev/null; then
        echo "PHP-FPM already started"
      else
        echo "==============   Starting phpfpm..."
        ${pkgs.php}/bin/php-fpm -p ${phpDir} -y ${phpConf} -c ${phpIni}
      fi

      if test -f ${mysqlDir}/data/mysqld.pid && ps -p $(cat ${mysqlDir}/data/mysqld.pid) > /dev/null; then
        echo "Mysql already started"
      else
        echo "==============   Starting mysql..."
        echo "pour activer logs mysql:"
        echo "start-stop-daemon --stop --pidfile nixfiles/mysql/data/mysqld.pid"
        echo "${pkgs.mysql57}/bin/mysqld --defaults-extra-file=${mysqlConf} --general_log=1 --general_log_file=${mysqlDir}/tmp/requests.log &)"
        echo ""
        echo ""
        test -e ${mysqlDir}/data/mysql || (${pkgs.mysql57}/bin/mysqld --initialize --basedir=${pkgs.mysql57} --datadir=${mysqlDir}/data 2> ${mysqlDir}/tmp/mysql_err.log && touch ${mysqlDir}/data/initRequired)
        ${pkgs.mysql57}/bin/mysqld --defaults-extra-file=${mysqlConf} &
        test -e ${mysqlDir}/data/initRequired && (echo "Initializing root password..." && sleep 5 && mysqladmin -uroot -h127.0.0.1 -P${cfg.mysqlPort} -p$(grep root@localhost ${mysqlDir}/tmp/mysql_err.log| awk '{print $NF}') password "${cfg.mysqlPassword}" && rm -f ${mysqlDir}/data/initRequired)
      fi
    }
    startServices
  '';

}
