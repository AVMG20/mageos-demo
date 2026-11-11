# Private single-node OpenSearch for Mage-OS catalog search (index is rebuildable, no volume).
FROM opensearchproject/opensearch:2.19.1
ENV discovery.type=single-node \
    bootstrap.memory_lock=false \
    DISABLE_SECURITY_PLUGIN=true \
    DISABLE_INSTALL_DEMO_CONFIG=true \
    OPENSEARCH_JAVA_OPTS="-Xms512m -Xmx512m"
USER opensearch
EXPOSE 9200
