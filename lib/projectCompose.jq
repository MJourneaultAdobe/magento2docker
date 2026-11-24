def port($host; $container): "127.0.0.1:\($host):\($container)";
def health($test):
  {test: $test, interval: "5s", timeout: "10s", retries: 30, start_period: "20s"};
def service($name; $config; $settings):
  (if $name == "mariadb" or $name == "mysql" then
    {
      image: $config.image,
      environment: {
        MYSQL_DATABASE: $config.database, MYSQL_USER: $config.username,
        MYSQL_PASSWORD: $config.password, MYSQL_ROOT_PASSWORD: $config.rootPassword
      },
      ports: [port($config.port; 3306)],
      volumes: ["\($name)-data:/var/lib/mysql"],
      networks: {default: {aliases: ["db"]}},
      healthcheck: health(["CMD-SHELL", "MYSQL_PWD=\"$MYSQL_ROOT_PASSWORD\" " +
        (if $name == "mariadb" then "mariadb-admin" else "mysqladmin" end) +
        " ping -h 127.0.0.1 -u root --silent"])
    }
  elif $name == "opensearch" or $name == "elasticsearch" then
    {
      image: $config.image,
      environment: ({"discovery.type": "single-node"} +
        if $name == "opensearch" then
          {DISABLE_SECURITY_PLUGIN: "true", DISABLE_INSTALL_DEMO_CONFIG: "true", OPENSEARCH_JAVA_OPTS: "-Xms512m -Xmx512m"}
        else {"xpack.security.enabled": "false", ES_JAVA_OPTS: "-Xms512m -Xmx512m"} end),
      ports: [port($config.port; 9200)],
      volumes: ["\($name)-data:/usr/share/\($name)/data"],
      networks: {default: {aliases: ["search_engine"]}},
      healthcheck: health(["CMD", "curl", "-fsS", "http://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=5s"])
    }
  elif $name == "redis" or $name == "valkey" then
    ($name + "-server") as $server |
    ($name + "-cli") as $client |
    {
      image: $config.image,
      environment: {REDISCLI_AUTH: $config.password, VALKEYCLI_AUTH: $config.password},
      command: [$server, "--appendonly", "yes", "--requirepass", $config.password],
      ports: [port($config.port; 6379)],
      volumes: ["\($name)-data:/data"],
      networks: {default: {aliases: ["db_cache"]}},
      healthcheck: health(["CMD", $client, "ping"])
    }
  elif $name == "rabbitmq" then
    {
      image: $config.image,
      environment: {RABBITMQ_DEFAULT_USER: $config.username, RABBITMQ_DEFAULT_PASS: $config.password},
      ports: [port($config.port; 5672), port($config.managementPort; 15672)],
      volumes: ["rabbitmq-data:/var/lib/rabbitmq"],
      networks: {default: {aliases: ["message_broker"]}},
      healthcheck: health(["CMD", "rabbitmq-diagnostics", "-q", "ping"])
    }
  elif $name == "varnish" then
    {
      image: $config.image,
      command: ["-p", "default_keep=300"],
      environment: {VARNISH_SIZE: "2G"},
      tmpfs: ["/var/lib/varnish:exec"],
      ports: [port($config.port; 80)],
      volumes: [{type:"bind", source:($installation + "/services/web-cache/default.vcl"), target:"/etc/varnish/default.vcl", read_only:true}],
      depends_on: {web: {condition: "service_healthy"}},
      healthcheck: health(["CMD", "varnishadm", "ping"])
    }
  elif $name == "mailcatcher" then
    {
      image: $config.image,
      platform: "linux/amd64",
      ports: [port($config.port; 1080), port($config.smtpPort; 1025)]
    }
  elif $name == "blackfire" then
    {
      image: $config.image,
      environment: {BLACKFIRE_SERVER_ID:$config.serverId, BLACKFIRE_SERVER_TOKEN:$config.serverToken},
      ports: [port($config.port; 8707)]
    }
  elif $name == "selenium" then
    {
      image: $config.image,
      platform: "linux/amd64",
      shm_size: "2gb",
      ports: [port($config.port; 4444), port($config.vncPort; 5900)]
    }
  elif $name == "web" then
    {
      image: $config.image,
      build: {
        context: $installation,
        dockerfile: "services/web-servers/apache/Dockerfile",
        target: "web_server",
        args: {
          M2D_WEB_SERVER_PHP_VERSION: $config.version, M2D_WEB_SERVER_OS:$config.os,
          M2D_XDEBUG_IDE_KEY: $config.ideKey, M2D_WEB_SERVER_PHP_MEMORY_LIMIT:$config.memoryLimit,
          M2D_ENABLE_MAILCATCHER:(if $settings.services | index("mailcatcher") != null then "yes" else "no" end),
          M2D_ENABLE_BLACKFIRE:(if $settings.services | index("blackfire") != null then "yes" else "no" end)
        }
      },
      environment: {
        MAGENTO_CLOUD_CLI_TOKEN: $config.cloudToken,
        M2D_WEB_SERVER_PHP_MEMORY_LIMIT:$config.memoryLimit,
        BLACKFIRE_CLIENT_ID:($settings.serviceSettings.blackfire.clientId // ""),
        BLACKFIRE_CLIENT_TOKEN:($settings.serviceSettings.blackfire.clientToken // "")
      },
      ports: [port($config.port; 80), port($config.httpsPort; 443), port($config.sshPort; 22)],
      volumes: [
        {type: "bind", source: $settings.sourceDirectory, target: "/var/www/html"},
        "web-home:/home", "web-root:/root",
        {type: "bind", source:($state + "/auth.json"), target:"/run/m2d/auth.json", read_only:true},
        {type: "bind", source:($state + "/gitconfig"), target:"/run/m2d/gitconfig", read_only:true}
      ],
      extra_hosts: ["host.docker.internal:host-gateway"],
      cap_add: ["SYS_PTRACE"],
      healthcheck: health(["CMD", "php", "-r", "exit(@fsockopen(\"127.0.0.1\", 80) ? 0 : 1);"])
    }
  else error("Unsupported service: " + $name) end) + {restart: "unless-stopped"};

. as $settings |
{
  name: .projectName,
  services: (reduce .services[] as $name ({}; .[$name] = service($name; $settings.serviceSettings[$name]; $settings))),
  volumes: (reduce .services[] as $name ({};
    if $name == "web" then . + {"web-home": {}, "web-root": {}}
    elif ($name | IN("mariadb","mysql","opensearch","elasticsearch","redis","valkey","rabbitmq")) then .[$name + "-data"] = {}
    else . end))
}
# Compose interpolates every string, including passwords; escape literal dollars.
| walk(if type == "string" then gsub("\\$"; "$$") else . end)
