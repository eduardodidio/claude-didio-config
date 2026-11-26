var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __generator = (this && this.__generator) || function (thisArg, body) {
    var _ = { label: 0, sent: function() { if (t[0] & 1) throw t[1]; return t[1]; }, trys: [], ops: [] }, f, y, t, g = Object.create((typeof Iterator === "function" ? Iterator : Object).prototype);
    return g.next = verb(0), g["throw"] = verb(1), g["return"] = verb(2), typeof Symbol === "function" && (g[Symbol.iterator] = function() { return this; }), g;
    function verb(n) { return function (v) { return step([n, v]); }; }
    function step(op) {
        if (f) throw new TypeError("Generator is already executing.");
        while (g && (g = 0, op[0] && (_ = 0)), _) try {
            if (f = 1, y && (t = op[0] & 2 ? y["return"] : op[0] ? y["throw"] || ((t = y["return"]) && t.call(y), 0) : y.next) && !(t = t.call(y, op[1])).done) return t;
            if (y = 0, t) op = [op[0] & 2, t.value];
            switch (op[0]) {
                case 0: case 1: t = op; break;
                case 4: _.label++; return { value: op[1], done: false };
                case 5: _.label++; y = op[1]; op = [0]; continue;
                case 7: op = _.ops.pop(); _.trys.pop(); continue;
                default:
                    if (!(t = _.trys, t = t.length > 0 && t[t.length - 1]) && (op[0] === 6 || op[0] === 2)) { _ = 0; continue; }
                    if (op[0] === 3 && (!t || (op[1] > t[0] && op[1] < t[3]))) { _.label = op[1]; break; }
                    if (op[0] === 6 && _.label < t[1]) { _.label = t[1]; t = op; break; }
                    if (t && _.label < t[2]) { _.label = t[2]; _.ops.push(op); break; }
                    if (t[2]) _.ops.pop();
                    _.trys.pop(); continue;
            }
            op = body.call(thisArg, _);
        } catch (e) { op = [6, e]; y = 0; } finally { f = t = 0; }
        if (op[0] & 5) throw op[1]; return { value: op[0] ? op[1] : void 0, done: true };
    }
};
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'node:path';
import fs from 'node:fs/promises';
import { aggregateJsonDir, aggregatePipelineState, readBody, } from './vite-plugins/kanban-json';
function kanbanJsonPlugin() {
    return {
        name: 'didio-kanban-json',
        configureServer: function (server) {
            var _this = this;
            // GET /flags.json — aggregated flags
            server.middlewares.use('/flags.json', function (_req, res) { return __awaiter(_this, void 0, void 0, function () {
                var flagsDir, flags;
                return __generator(this, function (_a) {
                    switch (_a.label) {
                        case 0:
                            flagsDir = path.resolve(__dirname, '../logs/agents/flags');
                            return [4 /*yield*/, aggregateJsonDir(flagsDir)];
                        case 1:
                            flags = _a.sent();
                            res.setHeader('Content-Type', 'application/json');
                            res.setHeader('Cache-Control', 'no-store');
                            res.end(JSON.stringify(flags));
                            return [2 /*return*/];
                    }
                });
            }); });
            // GET /actions.json — aggregated actions
            server.middlewares.use('/actions.json', function (_req, res) { return __awaiter(_this, void 0, void 0, function () {
                var actionsDir, actions;
                return __generator(this, function (_a) {
                    switch (_a.label) {
                        case 0:
                            actionsDir = path.resolve(__dirname, '../logs/agents/actions');
                            return [4 /*yield*/, aggregateJsonDir(actionsDir)];
                        case 1:
                            actions = _a.sent();
                            res.setHeader('Content-Type', 'application/json');
                            res.setHeader('Cache-Control', 'no-store');
                            res.end(JSON.stringify(actions));
                            return [2 /*return*/];
                    }
                });
            }); });
            // GET /pipeline-state.json — aggregated pipeline state
            server.middlewares.use('/pipeline-state.json', function (_req, res) { return __awaiter(_this, void 0, void 0, function () {
                var logsDir, pipelines;
                return __generator(this, function (_a) {
                    switch (_a.label) {
                        case 0:
                            logsDir = path.resolve(__dirname, '../logs/agents');
                            return [4 /*yield*/, aggregatePipelineState(logsDir)];
                        case 1:
                            pipelines = _a.sent();
                            res.setHeader('Content-Type', 'application/json');
                            res.setHeader('Cache-Control', 'no-store');
                            res.end(JSON.stringify(pipelines));
                            return [2 /*return*/];
                    }
                });
            }); });
            // POST /api/actions — write action JSON file
            server.middlewares.use('/api/actions', function (req, res) { return __awaiter(_this, void 0, void 0, function () {
                var body, actionsDir, filename, _a;
                return __generator(this, function (_b) {
                    switch (_b.label) {
                        case 0:
                            if (req.method !== 'POST') {
                                res.statusCode = 405;
                                res.end(JSON.stringify({ error: 'Method not allowed' }));
                                return [2 /*return*/];
                            }
                            _b.label = 1;
                        case 1:
                            _b.trys.push([1, 5, , 6]);
                            return [4 /*yield*/, readBody(req)];
                        case 2:
                            body = _b.sent();
                            if (!body.action_id || typeof body.action_id !== 'string') {
                                res.statusCode = 400;
                                res.setHeader('Content-Type', 'application/json');
                                res.end(JSON.stringify({ error: 'Missing or invalid action_id' }));
                                return [2 /*return*/];
                            }
                            actionsDir = path.resolve(__dirname, '../logs/agents/actions');
                            return [4 /*yield*/, fs.mkdir(actionsDir, { recursive: true })];
                        case 3:
                            _b.sent();
                            filename = "".concat(body.action_id, ".json");
                            return [4 /*yield*/, fs.writeFile(path.join(actionsDir, filename), JSON.stringify(body, null, 2))];
                        case 4:
                            _b.sent();
                            res.setHeader('Content-Type', 'application/json');
                            res.end(JSON.stringify({ ok: true, file: filename }));
                            return [3 /*break*/, 6];
                        case 5:
                            _a = _b.sent();
                            res.statusCode = 400;
                            res.setHeader('Content-Type', 'application/json');
                            res.end(JSON.stringify({ error: 'Invalid JSON body' }));
                            return [3 /*break*/, 6];
                        case 6: return [2 /*return*/];
                    }
                });
            }); });
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
});
