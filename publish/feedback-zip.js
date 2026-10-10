"use strict";
/* Feedback document, ZIP files. Loaded before the four page scripts, and uses none of them.
   The export is a ZIP without compression: the JSON of the answers weighs a few kilobytes
   and the attachments are images and archives that are compressed already, so storing them
   as they are costs nothing and needs no library. Reading also accepts the usual deflate
   compression, through the browser's own decompressor, so a ZIP repacked by another program
   or by an agent still imports. ZIP64, encryption and multi-disk archives are refused. */
const feedbackZip = (() => {
  const LOCAL = 0x04034b50, CENTRAL = 0x02014b50, END = 0x06054b50;
  // Bit 11 of the flags: file names are UTF-8.
  const UTF8 = 0x0800;
  const table = new Uint32Array(256).map((_, n) => {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    return c >>> 0;
  });
  function crc32(bytes) {
    let c = 0xffffffff;
    for (let i = 0; i < bytes.length; i++) c = table[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  }
  function dosDateTime(date) {
    return {
      time: (date.getHours() << 11) | (date.getMinutes() << 5) | (date.getSeconds() >> 1),
      date: ((date.getFullYear() - 1980) << 9) | ((date.getMonth() + 1) << 5) | date.getDate(),
    };
  }
  // entries: [{name, blob}] -> a Blob of type application/zip.
  async function write(entries) {
    const encoder = new TextEncoder(), parts = [], central = [];
    const { time, date } = dosDateTime(new Date());
    let offset = 0;
    for (const { name, blob } of entries) {
      const bytes = new Uint8Array(await blob.arrayBuffer());
      const path = encoder.encode(name), crc = crc32(bytes);
      const local = new DataView(new ArrayBuffer(30));
      local.setUint32(0, LOCAL, true);
      local.setUint16(4, 20, true);
      local.setUint16(6, UTF8, true);
      local.setUint16(8, 0, true);
      local.setUint16(10, time, true);
      local.setUint16(12, date, true);
      local.setUint32(14, crc, true);
      local.setUint32(18, bytes.length, true);
      local.setUint32(22, bytes.length, true);
      local.setUint16(26, path.length, true);
      const head = new DataView(new ArrayBuffer(46));
      head.setUint32(0, CENTRAL, true);
      head.setUint16(4, 20, true);
      head.setUint16(6, 20, true);
      head.setUint16(8, UTF8, true);
      head.setUint16(10, 0, true);
      head.setUint16(12, time, true);
      head.setUint16(14, date, true);
      head.setUint32(16, crc, true);
      head.setUint32(20, bytes.length, true);
      head.setUint32(24, bytes.length, true);
      head.setUint16(28, path.length, true);
      head.setUint32(42, offset, true);
      parts.push(local, path, bytes);
      central.push(head, path);
      offset += 30 + path.length + bytes.length;
    }
    const size = central.reduce((sum, part) => sum + part.byteLength, 0);
    const end = new DataView(new ArrayBuffer(22));
    end.setUint32(0, END, true);
    end.setUint16(8, entries.length, true);
    end.setUint16(10, entries.length, true);
    end.setUint32(12, size, true);
    end.setUint32(16, offset, true);
    return new Blob([...parts, ...central, end], { type: "application/zip" });
  }
  // A Blob -> Map of file name to bytes. Folders are skipped; every file is checked by CRC.
  async function read(blob) {
    const unreadable = () => Error("Lo ZIP non è leggibile.");
    const buffer = await blob.arrayBuffer(), bytes = new Uint8Array(buffer), view = new DataView(buffer);
    let end = -1;
    for (let at = bytes.length - 22; at >= Math.max(0, bytes.length - 22 - 0xffff); at--) {
      if (view.getUint32(at, true) === END) {
        end = at;
        break;
      }
    }
    if (end < 0) throw unreadable();
    const count = view.getUint16(end + 10, true);
    let at = view.getUint32(end + 16, true);
    const decoder = new TextDecoder(), files = new Map();
    for (let n = 0; n < count; n++) {
      if (at + 46 > bytes.length || view.getUint32(at, true) !== CENTRAL) throw unreadable();
      const flags = view.getUint16(at + 8, true), method = view.getUint16(at + 10, true);
      const crc = view.getUint32(at + 16, true), packed = view.getUint32(at + 20, true);
      const size = view.getUint32(at + 24, true), nameLength = view.getUint16(at + 28, true);
      const skip = view.getUint16(at + 30, true) + view.getUint16(at + 32, true);
      const local = view.getUint32(at + 42, true);
      const name = decoder.decode(bytes.subarray(at + 46, at + 46 + nameLength));
      at += 46 + nameLength + skip;
      if (name.endsWith("/")) continue;
      if (flags & 1) throw Error("Lo ZIP è protetto da password.");
      if (local + 30 > bytes.length || view.getUint32(local, true) !== LOCAL) throw unreadable();
      const start = local + 30 + view.getUint16(local + 26, true) + view.getUint16(local + 28, true);
      if (start + packed > bytes.length) throw unreadable();
      let data = bytes.subarray(start, start + packed);
      if (method === 8) {
        const stream = new Blob([data]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
        data = new Uint8Array(await new Response(stream).arrayBuffer());
      } else if (method !== 0) throw Error("Lo ZIP usa una compressione non supportata.");
      if (data.length !== size || crc32(data) !== crc) throw Error("Un file dello ZIP è danneggiato: " + name);
      files.set(name, data);
    }
    return files;
  }
  return { write, read };
})();
