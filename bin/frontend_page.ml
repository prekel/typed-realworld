open! Base

let html =
  {|<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>RealWorld</title>
    <style>
      :root { font-family: system-ui, sans-serif; color: #172033; background: #f5f7fb; }
      * { box-sizing: border-box; }
      body { margin: 0; }
      main { width: min(920px, calc(100% - 32px)); margin: 40px auto 80px; }
      header { display: flex; align-items: baseline; justify-content: space-between; gap: 16px; margin-bottom: 28px; }
      h1 { margin: 0; font-size: 2rem; }
      h2 { margin: 0 0 16px; font-size: 1.2rem; }
      p { line-height: 1.5; }
      .muted { color: #657188; }
      .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 20px; }
      .panel, .article { background: white; border: 1px solid #dce2eb; border-radius: 14px; padding: 20px; }
      .panel { margin-bottom: 20px; }
      label { display: block; margin: 12px 0 5px; font-weight: 600; }
      input, textarea { width: 100%; padding: 10px 12px; border: 1px solid #bfc8d8; border-radius: 8px; font: inherit; }
      textarea { min-height: 110px; resize: vertical; }
      button { margin: 14px 8px 0 0; padding: 10px 15px; border: 0; border-radius: 8px; background: #2c66d6; color: white; font: inherit; cursor: pointer; }
      button.secondary { background: #e6ebf4; color: #24334c; }
      button:disabled { opacity: .55; cursor: wait; }
      .message { padding: 11px 14px; margin: 0 0 20px; border-radius: 8px; background: #e9f1ff; }
      .message.error { background: #ffeded; color: #a52828; }
      .article { margin: 12px 0; }
      .article h3 { margin: 0 0 6px; }
      .article p { margin: 0 0 8px; }
      .article small { color: #657188; }
    </style>
    <script defer src="/app.js"></script>
  </head>
  <body><div id="app"></div></body>
</html>
|}
;;
