export class DocmdCliNotFoundError extends Error {
  constructor(command: string) {
    super(`DocMD CLI could not be started because ${command} was not found.`);
    this.name = 'DocmdCliNotFoundError';
  }
}