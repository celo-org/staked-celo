/* eslint-disable  @typescript-eslint/no-explicit-any */
import chalk from "chalk";

class Log {
  level: string;

  constructor(level = "default") {
    this.level = level;
  }

  public log(msg: string, supportingDetails?: any): void {
    this.emitLogMessage("log", chalk.grey(msg), supportingDetails);
  }
  public debug(msg: string, supportingDetails?: any): void {
    if (this.level === "debug") {
      this.emitLogMessage("debug", chalk.green(msg), supportingDetails);
    }
  }
  public info(msg: string, supportingDetails?: any): void {
    if (this.level === "info") {
      this.emitLogMessage("info", chalk.blue(msg), supportingDetails);
    }
  }
  public warning(msg: string, supportingDetails?: any): void {
    this.emitLogMessage("warn", chalk.yellow(msg), supportingDetails);
  }
  public error(msg: string, supportingDetails?: any): void {
    this.emitLogMessage("error", chalk.red(msg), supportingDetails);
  }

  private emitLogMessage(
    msgType: "log" | "debug" | "info" | "warn" | "error",
    msg: string,
    supportingDetails: any[]
  ) {
    if (supportingDetails !== undefined) {
      console[msgType](msg, supportingDetails);
    } else {
      console[msgType](msg);
    }
  }

  public setLogLevel(level: string): void {
    this.level = level;
  }
}

export const taskLogger = new Log();
