import json
import os

md_path = r'd:\mini_project2\MASTER_PROJECT_REPORT_AND_BUILD_LOG.md'
with open(md_path, 'r', encoding='utf-8') as f:
    raw_md = f.read()

escaped_md = json.dumps(raw_md)

html_template = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Master Project Report & Build Log - Zynq-7000 Video Accelerator</title>
    
    <!-- Google Fonts -->
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Fira+Code:wght@400;500;600&family=Inter:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
    
    <!-- Marked.js (Markdown Parser) -->
    <script src="https://cdn.jsdelivr.net/npm/marked@9.1.6/marked.min.js"></script>
    
    <!-- Mermaid.js (Diagram Engine) -->
    <script src="https://cdn.jsdelivr.net/npm/mermaid@10.8.0/dist/mermaid.min.js"></script>

    <style>
        :root {
            --bg-primary: #0b0f19;
            --bg-secondary: #111827;
            --bg-card: #1f2937;
            --border-color: #374151;
            --text-main: #f3f4f6;
            --text-muted: #9ca3af;
            --accent-cyan: #06b6d4;
            --accent-blue: #3b82f6;
            --accent-purple: #8b5cf6;
            --accent-green: #10b981;
            --accent-orange: #f59e0b;
            --code-bg: #030712;
        }

        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }

        body {
            background-color: var(--bg-primary);
            color: var(--text-main);
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.7;
            font-size: 15px;
            padding-bottom: 80px;
        }

        /* Top Sticky Header */
        .top-navbar {
            position: sticky;
            top: 0;
            z-index: 1000;
            background: rgba(11, 15, 25, 0.94);
            backdrop-filter: blur(12px);
            border-bottom: 1px solid var(--border-color);
            padding: 12px 32px;
            display: flex;
            align-items: center;
            justify-content: space-between;
        }

        .brand-container {
            display: flex;
            align-items: center;
            gap: 12px;
            flex-wrap: wrap;
        }

        .brand-badge {
            background: linear-gradient(135deg, #06b6d4, #3b82f6);
            color: #fff;
            font-weight: 700;
            font-size: 12px;
            padding: 4px 10px;
            border-radius: 6px;
            letter-spacing: 0.5px;
            text-transform: uppercase;
        }

        .brand-title {
            font-weight: 700;
            font-size: 16px;
            color: #fff;
        }

        .actions-group {
            display: flex;
            align-items: center;
            gap: 12px;
        }

        .btn {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            padding: 8px 16px;
            border-radius: 6px;
            font-size: 13px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.2s ease;
            text-decoration: none;
            border: 1px solid transparent;
        }

        .btn-primary {
            background: #2563eb;
            color: white;
        }

        .btn-primary:hover {
            background: #1d4ed8;
            box-shadow: 0 0 15px rgba(37, 99, 235, 0.5);
        }

        .btn-secondary {
            background: var(--bg-card);
            color: var(--text-main);
            border: 1px solid var(--border-color);
        }

        .btn-secondary:hover {
            background: #374151;
        }

        /* Main Container */
        .report-container {
            max-width: 1200px;
            margin: 40px auto;
            padding: 0 32px;
        }

        /* Typography & Markdown Elements */
        h1 {
            font-size: 2.2rem;
            font-weight: 800;
            color: #ffffff;
            margin-top: 48px;
            margin-bottom: 24px;
            padding-bottom: 12px;
            border-bottom: 2px solid #374151;
            letter-spacing: -0.5px;
        }

        h2 {
            font-size: 1.6rem;
            font-weight: 700;
            color: var(--accent-cyan);
            margin-top: 36px;
            margin-bottom: 16px;
            letter-spacing: -0.3px;
        }

        h3 {
            font-size: 1.25rem;
            font-weight: 600;
            color: #93c5fd;
            margin-top: 28px;
            margin-bottom: 12px;
        }

        h4 {
            font-size: 1.05rem;
            font-weight: 600;
            color: #a7f3d0;
            margin-top: 20px;
            margin-bottom: 8px;
        }

        p {
            margin-bottom: 16px;
            color: #e5e7eb;
        }

        strong {
            color: #ffffff;
            font-weight: 600;
        }

        /* Tables */
        table {
            width: 100%;
            border-collapse: separate;
            border-spacing: 0;
            margin: 24px 0;
            border-radius: 8px;
            overflow: hidden;
            border: 1px solid var(--border-color);
            background-color: var(--bg-secondary);
        }

        th {
            background-color: var(--bg-card);
            color: #f9fafb;
            font-weight: 600;
            text-align: left;
            padding: 12px 16px;
            border-bottom: 1px solid var(--border-color);
            font-size: 13px;
            letter-spacing: 0.3px;
        }

        td {
            padding: 12px 16px;
            border-bottom: 1px solid #1f2937;
            color: #d1d5db;
            font-size: 14px;
            vertical-align: top;
        }

        tr:last-child td {
            border-bottom: none;
        }

        tr:hover td {
            background-color: rgba(55, 65, 81, 0.4);
        }

        /* Code Blocks & Inline Code */
        code {
            font-family: 'Fira Code', Consolas, Monaco, monospace;
            font-size: 13px;
            background-color: rgba(55, 65, 81, 0.6);
            color: #38bdf8;
            padding: 2px 6px;
            border-radius: 4px;
        }

        pre {
            background-color: var(--code-bg);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            padding: 18px;
            margin: 20px 0;
            overflow-x: auto;
        }

        pre code {
            background-color: transparent;
            color: #e2e8f0;
            padding: 0;
            font-size: 13.5px;
            line-height: 1.6;
        }

        /* Mermaid Diagrams Container */
        .mermaid {
            background-color: #0f172a;
            border: 1px solid #1e293b;
            border-radius: 10px;
            padding: 24px;
            margin: 28px 0;
            text-align: center;
            overflow-x: auto;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.4);
        }

        .mermaid svg {
            max-width: 100% !important;
            height: auto !important;
        }

        /* Blockquotes / Callouts */
        blockquote {
            border-left: 4px solid var(--accent-cyan);
            background-color: rgba(6, 182, 212, 0.08);
            padding: 14px 20px;
            margin: 20px 0;
            border-radius: 0 8px 8px 0;
            color: #cbd5e1;
        }

        /* Lists */
        ul, ol {
            margin-bottom: 20px;
            padding-left: 28px;
            color: #d1d5db;
        }

        li {
            margin-bottom: 8px;
        }

        hr {
            border: none;
            height: 1px;
            background: linear-gradient(90deg, transparent, var(--border-color), transparent);
            margin: 40px 0;
        }

        /* Status & Diagnostic Tags */
        .badge-pill {
            display: inline-block;
            font-size: 11px;
            font-weight: 600;
            padding: 3px 8px;
            border-radius: 12px;
            margin-right: 6px;
        }

        .badge-green { background: rgba(16, 185, 129, 0.2); color: #34d399; border: 1px solid rgba(16, 185, 129, 0.4); }
        .badge-blue  { background: rgba(59, 130, 246, 0.2); color: #60a5fa; border: 1px solid rgba(59, 130, 246, 0.4); }
        .badge-yellow{ background: rgba(245, 158, 11, 0.2); color: #fbbf24; border: 1px solid rgba(245, 158, 11, 0.4); }

        /* Print Styles */
        @media print {
            body {
                background-color: #ffffff !important;
                color: #111827 !important;
                font-size: 11pt;
                padding: 0;
            }

            .top-navbar {
                display: none !important;
            }

            .report-container {
                max-width: 100% !important;
                margin: 0 !important;
                padding: 0 8mm !important;
            }

            h1, h2, h3, h4, strong {
                color: #111827 !important;
            }

            h1 {
                page-break-before: always;
                border-bottom: 2px solid #111827;
            }

            h1:first-of-type {
                page-break-before: avoid;
            }

            table {
                background-color: #ffffff !important;
                border: 1px solid #d1d5db !important;
                page-break-inside: avoid;
            }

            th {
                background-color: #f3f4f6 !important;
                color: #111827 !important;
                border-bottom: 2px solid #9ca3af !important;
            }

            td {
                color: #1f2937 !important;
                border-bottom: 1px solid #e5e7eb !important;
            }

            pre, code {
                background-color: #f8fafc !important;
                color: #0f172a !important;
                border: 1px solid #cbd5e1 !important;
                page-break-inside: avoid;
            }

            .mermaid {
                background-color: #ffffff !important;
                border: 1px solid #e2e8f0 !important;
                box-shadow: none !important;
                page-break-inside: avoid;
            }

            blockquote {
                background-color: #f0fdf4 !important;
                border-left: 4px solid #16a34a !important;
                color: #14532d !important;
            }
        }
    </style>
</head>
<body>

    <!-- Sticky Navigation Bar -->
    <header class="top-navbar">
        <div class="brand-container">
            <span class="brand-badge">Zynq-7000</span>
            <span class="brand-title">Master Project Report & Build Log</span>
            <span class="badge-pill badge-green">Timing Met (+0.204ns)</span>
            <span class="badge-pill badge-blue">50 MHz Master Clock</span>
            <span class="badge-pill badge-yellow">ZedBoard XC7Z020</span>
        </div>
        <div class="actions-group">
            <button class="btn btn-secondary" onclick="downloadMarkdown()">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path><polyline points="7 10 12 15 17 10"></polyline><line x1="12" y1="15" x2="12" y2="3"></line></svg>
                Download .MD
            </button>
            <button class="btn btn-primary" onclick="window.print()">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="6 9 6 2 18 2 18 9"></polyline><path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"></path><rect x="6" y="14" width="12" height="8"></rect></svg>
                Print / Save as PDF
            </button>
        </div>
    </header>

    <!-- Main Content Area -->
    <main class="report-container" id="report-target"></main>

    <script>
        // Raw Markdown Content
        const markdownSource = """ + escaped_md + """;

        // Download Markdown Function
        function downloadMarkdown() {
            const blob = new Blob([markdownSource], { type: 'text/markdown;charset=utf-8;' });
            const url = URL.createObjectURL(blob);
            const link = document.createElement('a');
            link.href = url;
            link.download = 'MASTER_PROJECT_REPORT_AND_BUILD_LOG.md';
            link.click();
            URL.revokeObjectURL(url);
        }

        // Initialize Mermaid
        mermaid.initialize({
            startOnLoad: false,
            theme: 'dark',
            themeVariables: {
                fontFamily: 'Inter, sans-serif',
                primaryColor: '#1e3a8a',
                primaryTextColor: '#f8fafc',
                primaryBorderColor: '#3b82f6',
                lineColor: '#60a5fa',
                secondaryColor: '#1e293b',
                tertiaryColor: '#0f172a'
            }
        });

        // Custom Renderer for Marked to handle Mermaid code fences
        const renderer = new marked.Renderer();
        const originalCode = renderer.code.bind(renderer);

        renderer.code = function(code, language) {
            if (language === 'mermaid') {
                return '<div class="mermaid">' + code + '</div>';
            }
            return originalCode(code, language);
        };

        marked.setOptions({
            renderer: renderer,
            gfm: true,
            breaks: false
        });

        // Render Markdown into DOM
        document.getElementById('report-target').innerHTML = marked.parse(markdownSource);

        // Run Mermaid on all generated .mermaid divs
        mermaid.run({
            querySelector: '.mermaid'
        });
    </script>
</body>
</html>
"""

with open(r'd:\mini_project2\docs\MASTER_PROJECT_REPORT_AND_BUILD_LOG.html', 'w', encoding='utf-8') as f:
    f.write(html_template)

with open(r'd:\mini_project2\MASTER_PROJECT_REPORT_AND_BUILD_LOG.html', 'w', encoding='utf-8') as f:
    f.write(html_template)

print('Successfully generated HTML reports:')
print('  docs:', os.path.getsize(r'd:\mini_project2\docs\MASTER_PROJECT_REPORT_AND_BUILD_LOG.html'), 'bytes')
print('  root:', os.path.getsize(r'd:\mini_project2\MASTER_PROJECT_REPORT_AND_BUILD_LOG.html'), 'bytes')
