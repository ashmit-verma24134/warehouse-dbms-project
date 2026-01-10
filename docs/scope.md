## Project Scope

This project models a warehouse-centric system where products are procured from producers in batches, stored under capacity constraints, and sold to customers using a soft-commit order mechanism.

The system enforces all business rules at the database level using constraints, triggers, and transactions. The application layer only triggers database operations.

In scope:
- Batch-based procurement
- Inventory state management
- Soft commit orders
- Traceability

Out of scope:
- Payment gateways
- Mobile app
- External APIs
