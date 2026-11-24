ARG M2D_SEARCH_ENGINE_VENDOR='opensearch'
ARG M2D_SEARCH_ENGINE_IMAGE='opensearchproject/opensearch:2'

FROM ${M2D_SEARCH_ENGINE_IMAGE} AS m2d_search_engine_opensearch
ENV DISABLE_INSTALL_DEMO_CONFIG=true \
    DISABLE_SECURITY_PLUGIN=true \
    discovery.type=single-node \
    plugins.security.disabled=true \
    http.host=0.0.0.0 \
    http.port=9200

FROM ${M2D_SEARCH_ENGINE_IMAGE} AS m2d_search_engine_elasticsearch
COPY --chown=elasticsearch:elasticsearch services/search-engines/etc/elasticsearch.yml /usr/share/elasticsearch/config/

FROM m2d_search_engine_${M2D_SEARCH_ENGINE_VENDOR} AS m2d_search_engine
