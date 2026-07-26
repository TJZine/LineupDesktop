export function decodeXmlEntities(value: string): string {
  return value.replace(/&([^&;]+);/gu, (reference, entity: string) => {
    const decoded = decodeXmlEntity(entity);
    return decoded ?? reference;
  });
}

function decodeXmlEntity(entity: string): string | null {
  switch (entity) {
    case 'amp':
      return '&';
    case 'apos':
      return "'";
    case 'gt':
      return '>';
    case 'lt':
      return '<';
    case 'quot':
      return '"';
  }

  const hexMatch = /^#x([0-9a-f]+)$/iu.exec(entity);
  const decimalMatch = /^#([0-9]+)$/u.exec(entity);
  const digits = hexMatch?.[1] ?? decimalMatch?.[1];
  if (!digits) {
    return null;
  }

  const codePoint = Number.parseInt(digits, hexMatch ? 16 : 10);
  return isValidXmlCodePoint(codePoint) ? String.fromCodePoint(codePoint) : null;
}

function isValidXmlCodePoint(codePoint: number): boolean {
  return (
    Number.isInteger(codePoint) &&
    (codePoint === 0x9 ||
      codePoint === 0xa ||
      codePoint === 0xd ||
      (codePoint >= 0x20 && codePoint <= 0xd7ff) ||
      (codePoint >= 0xe000 && codePoint <= 0xfffd) ||
      (codePoint >= 0x10000 && codePoint <= 0x10ffff))
  );
}
