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
/**
 * Vite plugin helpers for serving Kanban JSON data from logs/agents/.
 * Dev-server only — not included in production builds.
 */
import fs from 'node:fs/promises';
import path from 'node:path';
/**
 * Read all .json files from a directory and return their parsed contents
 * as an array. Corrupt/unreadable files are silently skipped.
 * Returns [] if the directory does not exist or is empty.
 */
export function aggregateJsonDir(dir) {
    return __awaiter(this, void 0, void 0, function () {
        var files, jsons, results, _i, jsons_1, f, content, _a, _b;
        return __generator(this, function (_c) {
            switch (_c.label) {
                case 0:
                    _c.trys.push([0, 8, , 9]);
                    return [4 /*yield*/, fs.readdir(dir)];
                case 1:
                    files = _c.sent();
                    jsons = files.filter(function (f) { return f.endsWith('.json'); });
                    results = [];
                    _i = 0, jsons_1 = jsons;
                    _c.label = 2;
                case 2:
                    if (!(_i < jsons_1.length)) return [3 /*break*/, 7];
                    f = jsons_1[_i];
                    _c.label = 3;
                case 3:
                    _c.trys.push([3, 5, , 6]);
                    return [4 /*yield*/, fs.readFile(path.join(dir, f), 'utf-8')];
                case 4:
                    content = _c.sent();
                    results.push(JSON.parse(content));
                    return [3 /*break*/, 6];
                case 5:
                    _a = _c.sent();
                    return [3 /*break*/, 6];
                case 6:
                    _i++;
                    return [3 /*break*/, 2];
                case 7: return [2 /*return*/, results];
                case 8:
                    _b = _c.sent();
                    return [2 /*return*/, []];
                case 9: return [2 /*return*/];
            }
        });
    });
}
/**
 * Read all pipeline-*.state.json files from logsDir and return their
 * parsed contents as an array. Corrupt files are silently skipped.
 */
export function aggregatePipelineState(logsDir) {
    return __awaiter(this, void 0, void 0, function () {
        var files, pipelineFiles, results, _i, pipelineFiles_1, f, content, _a, _b;
        return __generator(this, function (_c) {
            switch (_c.label) {
                case 0:
                    _c.trys.push([0, 8, , 9]);
                    return [4 /*yield*/, fs.readdir(logsDir)];
                case 1:
                    files = _c.sent();
                    pipelineFiles = files.filter(function (f) { return /^pipeline-.*\.state\.json$/.test(f); });
                    results = [];
                    _i = 0, pipelineFiles_1 = pipelineFiles;
                    _c.label = 2;
                case 2:
                    if (!(_i < pipelineFiles_1.length)) return [3 /*break*/, 7];
                    f = pipelineFiles_1[_i];
                    _c.label = 3;
                case 3:
                    _c.trys.push([3, 5, , 6]);
                    return [4 /*yield*/, fs.readFile(path.join(logsDir, f), 'utf-8')];
                case 4:
                    content = _c.sent();
                    results.push(JSON.parse(content));
                    return [3 /*break*/, 6];
                case 5:
                    _a = _c.sent();
                    return [3 /*break*/, 6];
                case 6:
                    _i++;
                    return [3 /*break*/, 2];
                case 7: return [2 /*return*/, results];
                case 8:
                    _b = _c.sent();
                    return [2 /*return*/, []];
                case 9: return [2 /*return*/];
            }
        });
    });
}
/**
 * Read the full request body and parse it as JSON.
 */
export function readBody(req) {
    return new Promise(function (resolve, reject) {
        var chunks = [];
        req.on('data', function (chunk) { return chunks.push(chunk); });
        req.on('end', function () {
            try {
                var body = JSON.parse(Buffer.concat(chunks).toString('utf-8'));
                resolve(body);
            }
            catch (err) {
                reject(err);
            }
        });
        req.on('error', reject);
    });
}
