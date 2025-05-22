import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

export class Logger {
  constructor(options = {}) {
    this.serviceName = options.serviceName || 'unknown';
    this.logDirectory = options.logDirectory || '/var/log/app';
    
    // Créer le chemin complet pour le répertoire de logs
    this.logPath = path.join(this.logDirectory, this.serviceName);
    
    // Créer le répertoire de logs s'il n'existe pas
    try {
      if (!fs.existsSync(this.logPath)) {
        fs.mkdirSync(this.logPath, { recursive: true });
      }
    } catch (error) {
      console.error(`Error creating log directory: ${error.message}`);
    }
    
    // Chemin du fichier de log
    this.logFilePath = path.join(this.logPath, 'service.log');
    
    // Vérifier si on peut écrire dans le fichier
    try {
      fs.accessSync(path.dirname(this.logFilePath), fs.constants.W_OK);
    } catch (error) {
      console.error(`Cannot write to log file: ${error.message}`);
      this.logFilePath = null;
    }
  }

  _writeLog(level, message, meta = {}) {
    const timestamp = new Date().toISOString();
    const logEntry = {
      timestamp,
      level,
      message,
      service: this.serviceName,
      ...meta
    };

    // Écrire dans le fichier de log
    if (this.logFilePath) {
      try {
        fs.appendFileSync(
          this.logFilePath,
          JSON.stringify(logEntry) + '\n'
        );
      } catch (error) {
        console.error(`Failed to write to log file: ${error.message}`);
      }
    }

    // Afficher également dans la console
    console.log(`[${timestamp}] [${level.toUpperCase()}] [${this.serviceName}] ${message}`);
  }

  info(message, meta = {}) {
    this._writeLog('info', message, meta);
  }

  warn(message, meta = {}) {
    this._writeLog('warn', message, meta);
  }

  error(message, meta = {}) {
    this._writeLog('error', message, meta);
  }

  debug(message, meta = {}) {
    this._writeLog('debug', message, meta);
  }
}

export default Logger;
