// Backward-compatible entry point. Prefer: npm run db:add-fife -- neon <appId> <appKey>
process.argv.splice(2, 0, 'neon');
await import('./add_fife');
