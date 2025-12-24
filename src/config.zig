const cfg = @import("config/mod.zig");

pub const ConfigError = cfg.ConfigError;
pub const AddressFamily = cfg.AddressFamily;
pub const Protocol = cfg.Protocol;
pub const Project = cfg.Project;
pub const Config = cfg.Config;

pub const Provider = cfg.Provider;
pub const UciProvider = cfg.UciProvider;
pub const JsonProvider = cfg.JsonProvider;

pub const loadFromProvider = cfg.loadFromProvider;
pub const loadFromUci = cfg.loadFromUci;
pub const loadFromJsonFile = cfg.loadFromJsonFile;

pub const parseBool = cfg.parseBool;
pub const parsePort = cfg.parsePort;
pub const parseFamily = cfg.parseFamily;
pub const parseProtocol = cfg.parseProtocol;
pub const dupeIfNonEmpty = cfg.dupeIfNonEmpty;
