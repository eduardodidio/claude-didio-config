/**
 * Vite plugin helpers for serving Kanban JSON data from logs/agents/.
 * Dev-server only — not included in production builds.
 */
import fs from 'node:fs/promises';
import path from 'node:path';
import type { IncomingMessage } from 'node:http';

/**
 * Read all .json files from a directory and return their parsed contents
 * as an array. Corrupt/unreadable files are silently skipped.
 * Returns [] if the directory does not exist or is empty.
 */
export async function aggregateJsonDir(dir: string): Promise<unknown[]> {
  try {
    const files = await fs.readdir(dir);
    const jsons = files.filter(f => f.endsWith('.json'));
    const results: unknown[] = [];
    for (const f of jsons) {
      try {
        const content = await fs.readFile(path.join(dir, f), 'utf-8');
        results.push(JSON.parse(content));
      } catch {
        // Skip corrupt or unreadable files
      }
    }
    return results;
  } catch {
    return [];
  }
}

/**
 * Read all pipeline-*.state.json files from logsDir and return their
 * parsed contents as an array. Corrupt files are silently skipped.
 */
export async function aggregatePipelineState(logsDir: string): Promise<unknown[]> {
  try {
    const files = await fs.readdir(logsDir);
    const pipelineFiles = files.filter(f => /^pipeline-.*\.state\.json$/.test(f));
    const results: unknown[] = [];
    for (const f of pipelineFiles) {
      try {
        const content = await fs.readFile(path.join(logsDir, f), 'utf-8');
        results.push(JSON.parse(content));
      } catch {
        // Skip corrupt or unreadable files
      }
    }
    return results;
  } catch {
    return [];
  }
}

/**
 * Read the full request body and parse it as JSON.
 */
export function readBody(req: IncomingMessage): Promise<Record<string, unknown>> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    req.on('data', (chunk: Buffer) => chunks.push(chunk));
    req.on('end', () => {
      try {
        const body = JSON.parse(Buffer.concat(chunks).toString('utf-8'));
        resolve(body);
      } catch (err) {
        reject(err);
      }
    });
    req.on('error', reject);
  });
}
