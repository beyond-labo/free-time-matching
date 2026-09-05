.PHONY: bootstrap verify export-openapi generate-api-client

bootstrap:
	bash scripts/bootstrap.sh

verify:
	bash scripts/verify.sh

export-openapi:
	pnpm --filter @himatch/backend export:openapi

generate-api-client:
	bash apps/ios/Scripts/generate-api-client.sh
