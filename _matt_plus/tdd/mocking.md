# When to mock

Mock at **system boundaries** only:

- External APIs (payment, email, and the like)
- Databases — sometimes; prefer a real test database
- Time and randomness
- The file system — sometimes

Leave these real:

- Your own classes and modules
- Internal collaborators
- Anything you control

## Designing for mockability

At a system boundary, shape the interface so a mock stays trivial.

**1. Inject the dependency.** Pass the external client in rather than building it inside:

```typescript
// Easy to mock
function processPayment(order, paymentClient) {
  return paymentClient.charge(order.total);
}

// Hard to mock
function processPayment(order) {
  const client = new StripeClient(process.env.STRIPE_KEY);
  return client.charge(order.total);
}
```

**2. Prefer SDK-style interfaces over one generic fetcher.** Give each external operation its own function instead of one function with conditional logic:

```typescript
// GOOD: each function is independently mockable
const api = {
  getUser: (id) => fetch(`/users/${id}`),
  getOrders: (userId) => fetch(`/users/${userId}/orders`),
  createOrder: (data) => fetch('/orders', { method: 'POST', body: data }),
};

// BAD: mocking needs conditional logic inside the mock
const api = {
  fetch: (endpoint, options) => fetch(endpoint, options),
};
```

The SDK shape buys four things:

- Each mock returns one specific shape
- No conditional logic in test setup
- It is visible which endpoints a test exercises
- Type safety per endpoint
