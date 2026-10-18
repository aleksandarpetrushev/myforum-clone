# Rails stays a modular monolith

My Forum's transactional workflows are still one product. Splitting events and registration into services would add failure modes before we have a scale problem that requires it.

Controllers, policies, and a few service objects are enough to keep the registration rules in one place. A later split can follow the outbox boundary. We are not drawing that line now.
