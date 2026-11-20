const path = require("path");
const jwt = require("jsonwebtoken");

const mockQuery = vi.fn();
const dbPath = path.resolve(__dirname, "../src/config/database.js");
require.cache[dbPath] = {
  id: dbPath,
  filename: dbPath,
  loaded: true,
  exports: { pool: { query: mockQuery } },
};
process.env.JWT_SECRET = "test-secret";

const servicePath = path.resolve(__dirname, "../src/services/realtime.js");
delete require.cache[servicePath];
const {
  setupSocketAuth,
  emitToTrustCircle,
  STAFF_ROOM,
} = require("../src/services/realtime");

/** Records which rooms a broadcast targeted. */
function fakeIo() {
  const sent = [];
  let onConnection = null;
  const chain = (rooms) => ({
    to: (room) => chain([...rooms, room]),
    emit: (event, payload) => sent.push({ rooms, event, payload }),
  });
  return {
    sent,
    to: (room) => chain([room]),
    emit: (event, payload) => sent.push({ rooms: ["*ALL*"], event, payload }),
    on: (name, fn) => {
      if (name === "connection") onConnection = fn;
    },
    connect: (socket) => onConnection(socket),
  };
}

function fakeSocket(auth = {}) {
  const handlers = {};
  return {
    rooms: new Set(),
    data: {},
    handshake: { auth, headers: {} },
    join(room) {
      this.rooms.add(room);
    },
    on(name, fn) {
      handlers[name] = fn;
    },
    fire: (name, payload) => handlers[name](payload),
  };
}

const token = (userId, role = "citizen") =>
  jwt.sign({ userId, role }, process.env.JWT_SECRET);

beforeEach(() => {
  mockQuery.mockReset();
});

describe("socket auth", () => {
  it("joins the user room from a valid handshake token", async () => {
    mockQuery.mockResolvedValue({ rows: [{ role: "citizen", is_active: true }] });
    const io = fakeIo();
    setupSocketAuth(io);
    const socket = fakeSocket({ token: token("u1") });
    await io.connect(socket);
    expect([...socket.rooms]).toEqual(["user:u1"]);
  });

  it("adds staff to the staff room using the live role", async () => {
    mockQuery.mockResolvedValue({ rows: [{ role: "leader", is_active: true }] });
    const io = fakeIo();
    setupSocketAuth(io);
    const socket = fakeSocket({ token: token("l1", "citizen") });
    await io.connect(socket);
    expect(socket.rooms.has(STAFF_ROOM)).toBe(true);
  });

  it("ignores the old authenticate { userId } form", async () => {
    const io = fakeIo();
    setupSocketAuth(io);
    const socket = fakeSocket();
    await io.connect(socket);
    await socket.fire("authenticate", { userId: "victim" });
    expect(socket.rooms.size).toBe(0);
  });

  it("rejects a forged token", async () => {
    const io = fakeIo();
    setupSocketAuth(io);
    const forged = jwt.sign({ userId: "victim" }, "wrong-secret");
    const socket = fakeSocket({ token: forged });
    await io.connect(socket);
    await socket.fire("authenticate", { token: forged });
    expect(socket.rooms.size).toBe(0);
  });

  it("gives no room to a deleted or disabled account", async () => {
    mockQuery.mockResolvedValue({ rows: [] });
    const io = fakeIo();
    setupSocketAuth(io);
    const socket = fakeSocket({ token: token("gone") });
    await io.connect(socket);
    expect(socket.rooms.size).toBe(0);
  });
});

describe("emitToTrustCircle", () => {
  it("targets staff and the sender's app contacts, never everyone", async () => {
    mockQuery.mockResolvedValue({
      rows: [{ contact_user_id: "c1" }, { contact_user_id: "c2" }, { contact_user_id: "c1" }],
    });
    const io = fakeIo();
    await emitToTrustCircle(io, "sender", "sos_alert", { id: "i1" });
    expect(io.sent).toHaveLength(1);
    expect(io.sent[0].rooms).toEqual([STAFF_ROOM, "user:c1", "user:c2"]);
    expect(io.sent[0].rooms).not.toContain("*ALL*");
  });
});
