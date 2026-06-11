const isProduction = process.env.NODE_ENV === "production";

const log = (...args) => {
  if (!isProduction) console.log(...args);
};

const warn = (...args) => console.warn(...args);

const error = (...args) => console.error(...args);

module.exports = { log, warn, error };
