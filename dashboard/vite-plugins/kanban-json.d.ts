import type { IncomingMessage } from 'node:http';
/**
 * Read all .json files from a directory and return their parsed contents
 * as an array. Corrupt/unreadable files are silently skipped.
 * Returns [] if the directory does not exist or is empty.
 */
export declare function aggregateJsonDir(dir: string): Promise<unknown[]>;
/**
 * Read all pipeline-*.state.json files from logsDir and return their
 * parsed contents as an array. Corrupt files are silently skipped.
 */
export declare function aggregatePipelineState(logsDir: string): Promise<unknown[]>;
/**
 * Read the full request body and parse it as JSON.
 */
export declare function readBody(req: IncomingMessage): Promise<Record<string, unknown>>;
