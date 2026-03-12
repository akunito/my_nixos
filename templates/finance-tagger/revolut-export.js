/**
 * Revolut Transaction Export Script
 *
 * Run this in the browser console while logged into app.revolut.com.
 * It paginates through all transactions across all pockets (accounts)
 * and downloads a JSON file with the full API data.
 *
 * Usage:
 *   1. Log in to app.revolut.com
 *   2. Open DevTools (F12) → Console tab
 *   3. Paste this entire script and press Enter
 *   4. Wait for completion (progress shown in console)
 *   5. A JSON file will be downloaded automatically
 */
(async function exportRevolutTransactions() {
  const BATCH_SIZE = 50;
  const DELAY_MS = 500;

  // --- Discover all pockets (accounts) ---
  console.log('[Revolut Export] Discovering accounts...');
  let pockets;
  try {
    const resp = await fetch('/api/retail/user/current/wallet', {
      credentials: 'include',
    });
    if (!resp.ok) throw new Error('Wallet API returned ' + resp.status);
    const wallet = await resp.json();
    pockets = wallet.pockets || [];
    console.log(
      '[Revolut Export] Found ' + pockets.length + ' pockets: ' +
      pockets.map(function(p) { return p.currency + ' (' + p.id + ')'; }).join(', ')
    );
  } catch (e) {
    console.error(
      '[Revolut Export] Failed to discover pockets. ' +
      'Make sure you are logged into app.revolut.com'
    );
    console.error(e);
    return;
  }

  if (pockets.length === 0) {
    console.error('[Revolut Export] No pockets found. Are you logged in?');
    return;
  }

  var allTransactions = [];
  var seenIds = {};

  for (var pi = 0; pi < pockets.length; pi++) {
    var pocket = pockets[pi];
    var pocketId = pocket.id;
    var currency = pocket.currency || 'unknown';
    console.log(
      '\n[Revolut Export] === Processing pocket: ' + currency +
      ' (' + pocketId + ') ==='
    );

    var to = Date.now();
    var pocketCount = 0;
    var emptyBatches = 0;

    while (true) {
      var url =
        '/api/retail/user/current/transactions/last?to=' + to +
        '&count=' + BATCH_SIZE +
        '&internalPocketId=' + pocketId;

      var batch;
      try {
        var resp = await fetch(url, { credentials: 'include' });
        if (!resp.ok) {
          if (resp.status === 429) {
            console.warn('[Revolut Export] Rate limited, waiting 5s...');
            await new Promise(function(r) { setTimeout(r, 5000); });
            continue;
          }
          throw new Error('API returned ' + resp.status);
        }
        batch = await resp.json();
      } catch (e) {
        console.error('[Revolut Export] Error fetching batch:', e);
        break;
      }

      if (!Array.isArray(batch) || batch.length === 0) {
        emptyBatches++;
        if (emptyBatches >= 2) break;
        to -= 1;
        continue;
      }
      emptyBatches = 0;

      var newInBatch = 0;
      for (var i = 0; i < batch.length; i++) {
        var tx = batch[i];
        var key = tx.id + '|' + (tx.legId || '');
        if (!seenIds[key]) {
          seenIds[key] = true;
          allTransactions.push(tx);
          newInBatch++;
        }
      }

      pocketCount += newInBatch;

      // Find earliest startedDate for next page
      var earliest = to;
      for (var i = 0; i < batch.length; i++) {
        var d = batch[i].startedDate || batch[i].createdDate || to;
        if (d < earliest) earliest = d;
      }
      var nextTo = earliest - 1;

      if (nextTo >= to) {
        console.warn('[Revolut Export] No pagination progress, stopping pocket.');
        break;
      }
      to = nextTo;

      var dateStr = new Date(to).toISOString().slice(0, 10);
      console.log(
        '[Revolut Export] ' + currency + ': +' + newInBatch +
        ' txns (' + pocketCount + ' total), going back to ' + dateStr
      );

      if (batch.length < BATCH_SIZE) break; // last page

      // Rate limit delay
      await new Promise(function(r) { setTimeout(r, DELAY_MS); });
    }

    console.log(
      '[Revolut Export] ' + currency + ': ' + pocketCount + ' transactions total'
    );
  }

  console.log(
    '\n[Revolut Export] === DONE === Total: ' +
    allTransactions.length + ' transactions'
  );

  // Sort by date descending
  allTransactions.sort(function(a, b) {
    return (b.startedDate || 0) - (a.startedDate || 0);
  });

  // Download as JSON
  var blob = new Blob(
    [JSON.stringify(allTransactions, null, 2)],
    { type: 'application/json' }
  );
  var dlUrl = URL.createObjectURL(blob);
  var a = document.createElement('a');
  a.href = dlUrl;
  var today = new Date().toISOString().slice(0, 10);
  a.download = 'revolut-transactions-' + today + '.json';
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(dlUrl);

  console.log('[Revolut Export] File downloaded: revolut-transactions-' + today + '.json');
})();
