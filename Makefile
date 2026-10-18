.PHONY: setup test dev

setup:
	docker compose up -d
	cd backend && bundle install && bin/rails db:prepare && bin/rails db:seed
	cd frontend && npm install
	cd personalization && go test ./...

test:
	cd backend && bundle exec rspec
	cd personalization && go test ./...
	cd frontend && npm test -- --watch=false

dev:
	@echo "Start each process in its own terminal:"
	@echo "  cd backend && bin/rails server"
	@echo "  cd backend && bundle exec sidekiq"
	@echo "  cd personalization && go run ./cmd/personalization"
	@echo "  cd frontend && npm start"
