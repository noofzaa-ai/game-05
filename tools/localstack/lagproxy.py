"""TCP proxy 127.0.0.1:LISTEN -> 127.0.0.1:TARGET adding DELAY ms each way and an optional KB/s cap (local tests only)."""
import asyncio, sys, time
LISTEN, TARGET, DELAY = int(sys.argv[1]), int(sys.argv[2]), float(sys.argv[3]) / 1000.0
RATE = float(sys.argv[4]) * 1024 if len(sys.argv) > 4 else 0.0  # bytes per second, 0 = unlimited


async def pipe(reader, writer, label):
    q = asyncio.Queue()
    async def rx():
        while True:
            data = await reader.read(65536)
            await q.put((time.monotonic() + DELAY, data))
            if not data:
                return
    async def tx():
        while True:
            due, data = await q.get()
            wait = due - time.monotonic()
            if wait > 0:
                await asyncio.sleep(wait)
            if not data:
                writer.close(); return
            if RATE > 0:
                await asyncio.sleep(len(data) / RATE)
            writer.write(data); await writer.drain()
    await asyncio.gather(rx(), tx(), return_exceptions=True)


async def handle(cr, cw):
    sr, sw = await asyncio.open_connection("127.0.0.1", TARGET)
    print("conn", flush=True)
    await asyncio.gather(pipe(cr, sw, "up"), pipe(sr, cw, "down"), return_exceptions=True)
    print("closed", flush=True)


async def main():
    server = await asyncio.start_server(handle, "127.0.0.1", LISTEN)
    async with server:
        await server.serve_forever()

asyncio.run(main())
