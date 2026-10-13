// Cloudflare Email Worker: shared addresses (home@…) -> several verified destinations.
// Email Routing rules take a single destination; fan-out needs a Worker (CF docs, 2026-10).
// ROUTES is a JSON plain_text binding {"addr@domain": ["dest", …]} set by deploy.sh from
// secrets/domains.nix, so no personal addresses live in this public repo.
let routes;

export default {
  async email(message, env) {
    routes ??= JSON.parse(env.ROUTES);
    const to = routes[message.to.toLowerCase()];
    if (!to) {
      message.setReject("unknown recipient");
      return;
    }
    const results = await Promise.allSettled(to.map((a) => message.forward(a)));
    // Reject only when nobody got it: the sender then gets a bounce instead of silent loss
    // (Email Routing keeps no copy). A partial failure still leaves one inbox with the mail.
    if (results.every((r) => r.status === "rejected")) {
      message.setReject("forwarding failed for every destination");
    }
  },
};
