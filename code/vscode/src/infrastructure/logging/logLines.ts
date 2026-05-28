export function splitLogLines(message: string): string[] {
  return message.split(/\r\n|\n|\r/);
}