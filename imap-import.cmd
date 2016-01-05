@echo off
cd /d "%~dp0"
java -cp "elasticsearch-2.1.1\imap\elasticsearch-importer-imap-0.9-beta-bin\lib\*" de.saly.elasticsearch.importer.imap.IMAPImporterCl -f "imap_importer_config.json"