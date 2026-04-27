Next recommended steps
	1	Replace <workspace>.sql.azuresynapse.net placeholder in main.bicep with your real Synapse FQDN, then plug in the CAAS landing-zone modules for VNet / private DNS zone groups.
	2	Run the T-SQL snippet in the Bicep file to create the Entra ID DB user for the App Service MSI and grant SELECT on the views only.
	3	Stand up an AI Search index safety-docs with a content_vector field + safety-docs-semantic semantic config; ingest your DOCX/XLSX through Azure AI Document Intelligence.
	4	Wire a minimal React canvas that consumes the SSE stream and renders the chart events with Vega-Lite.
