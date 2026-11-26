import { defineConfig, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'node:path';
import fs from 'node:fs/promises';
import {
  aggregateJsonDir,
  aggregatePipelineState,
  readBody,
} from './vite-plugins/kanban-json';

function kanbanJsonPlugin(): Plugin {
  return {
    name: 'didio-kanban-json',
    configureServer(server) {
      // GET /flags.json — aggregated flags
      server.middlewares.use('/flags.json', async (_req, res) => {
        const flagsDir = path.resolve(__dirname, '../logs/agents/flags');
        const flags = await aggregateJsonDir(flagsDir);
        res.setHeader('Content-Type', 'application/json');
        res.setHeader('Cache-Control', 'no-store');
        res.end(JSON.stringify(flags));
      });

      // GET /actions.json — aggregated actions
      server.middlewares.use('/actions.json', async (_req, res) => {
        const actionsDir = path.resolve(__dirname, '../logs/agents/actions');
        const actions = await aggregateJsonDir(actionsDir);
        res.setHeader('Content-Type', 'application/json');
        res.setHeader('Cache-Control', 'no-store');
        res.end(JSON.stringify(actions));
      });

      // GET /pipeline-state.json — aggregated pipeline state
      server.middlewares.use('/pipeline-state.json', async (_req, res) => {
        const logsDir = path.resolve(__dirname, '../logs/agents');
        const pipelines = await aggregatePipelineState(logsDir);
        res.setHeader('Content-Type', 'application/json');
        res.setHeader('Cache-Control', 'no-store');
        res.end(JSON.stringify(pipelines));
      });

      // POST /api/actions — write action JSON file
      server.middlewares.use('/api/actions', async (req, res) => {
        if (req.method !== 'POST') {
          res.statusCode = 405;
          res.end(JSON.stringify({ error: 'Method not allowed' }));
          return;
        }
        try {
          const body = await readBody(req);
          if (!body.action_id || typeof body.action_id !== 'string') {
            res.statusCode = 400;
            res.setHeader('Content-Type', 'application/json');
            res.end(JSON.stringify({ error: 'Missing or invalid action_id' }));
            return;
          }
          const actionsDir = path.resolve(__dirname, '../logs/agents/actions');
          await fs.mkdir(actionsDir, { recursive: true });
          const filename = `${body.action_id}.json`;
          await fs.writeFile(
            path.join(actionsDir, filename),
            JSON.stringify(body, null, 2),
          );
          res.setHeader('Content-Type', 'application/json');
          res.end(JSON.stringify({ ok: true, file: filename }));
        } catch {
          res.statusCode = 400;
          res.setHeader('Content-Type', 'application/json');
          res.end(JSON.stringify({ error: 'Invalid JSON body' }));
        }
      });
    },
  };
}

export default defineConfig({
  base: './',
  plugins: [react(), kanbanJsonPlugin()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'src'),
    },
  },
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
  },
} as any);
