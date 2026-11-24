ARG M2D_DB_ENGINE_IMAGE='mariadb:11.4'

FROM ${M2D_DB_ENGINE_IMAGE} AS m2d_db_engine
COPY services/db-engines/etc/mysql/my.cnf /etc/mysql/conf.d
