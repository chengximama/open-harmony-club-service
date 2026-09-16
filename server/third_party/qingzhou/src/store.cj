package qingzhou

import cangdb.*
import std.collection.*
import std.convert.*

/*
 * SPDX-License-Identifier: MIT
 *
 * QingZhou - RBAC data access layer on top of CangDB.
 *
 * Copyright (c) 2026 guowei
 * BIT Foundational Software And Systems Lab
 *
 * 基于 CangDB 嵌入式数据库的用户/角色/权限存储。
 * 表结构：
 *   users(id, username, password_hash, role_id)
 *   roles(id, name)
 *   permissions(id, code, name)
 *   role_permissions(role_id, permission_id)
 * RBAC 链：用户 -> 角色（单角色）-> 权限（多对多）。
 *
 * CangDB 能力边界（写查询时遵守）：
 *   - 仅支持 SELECT *（无单列投影）与等值比较 WHERE 列 = 值
 *   - 支持两表等值 JOIN，但不支持算术表达式
 *   - 分步查询 + 应用层组合，避免依赖复杂 SQL
 */

public class UserRow {
    public let id: Int64
    public let username: String
    public let passwordHash: String
    public let roleId: Int64
    public init(id: Int64, username: String, passwordHash: String, roleId: Int64) {
        this.id = id
        this.username = username
        this.passwordHash = passwordHash
        this.roleId = roleId
    }
}

public class RoleRow {
    public let id: Int64
    public let name: String
    public init(id: Int64, name: String) {
        this.id = id
        this.name = name
    }
}

public class PermRow {
    public let id: Int64
    public let code: String
    public let name: String
    public init(id: Int64, code: String, name: String) {
        this.id = id
        this.code = code
        this.name = name
    }
}

public class RbacStore {
    public let db: Db

    public init(path: String) {
        this.db = Db(path)
        // 首次打开才建表 + 灌种子数据
        if (db.findTable("users").isNone()) {
            db.exec("CREATE TABLE users (id INT, username TEXT, password_hash TEXT, role_id INT)")
        }
        if (db.findTable("roles").isNone()) {
            db.exec("CREATE TABLE roles (id INT, name TEXT)")
        }
        if (db.findTable("permissions").isNone()) {
            db.exec("CREATE TABLE permissions (id INT, code TEXT, name TEXT)")
        }
        if (db.findTable("role_permissions").isNone()) {
            db.exec("CREATE TABLE role_permissions (role_id INT, permission_id INT)")
        }
        seed()
    }

    /* 首次启动灌入种子数据：admin/user 两个角色、6 个权限、2 个用户。 */
    private func seed(): Unit {
        if (db.query("SELECT * FROM roles").rowCount() == 0) {
            db.exec("INSERT INTO roles VALUES (1, 'admin')")
            db.exec("INSERT INTO roles VALUES (2, 'user')")
            db.exec("INSERT INTO permissions VALUES (1, 'user:list', '查看用户')")
            db.exec("INSERT INTO permissions VALUES (2, 'user:create', '创建用户')")
            db.exec("INSERT INTO permissions VALUES (3, 'user:delete', '删除用户')")
            db.exec("INSERT INTO permissions VALUES (4, 'role:list', '查看角色')")
            db.exec("INSERT INTO permissions VALUES (5, 'perm:list', '查看权限')")
            db.exec("INSERT INTO permissions VALUES (6, 'dashboard:view', '查看仪表盘')")
            // admin 角色拥有全部 6 个权限
            for (i in 1..6) {
                db.exec("INSERT INTO role_permissions VALUES (1, ${i})")
            }
            // user 角色仅有 dashboard:view
            db.exec("INSERT INTO role_permissions VALUES (2, 6)")
        }
        if (db.query("SELECT * FROM users").rowCount() == 0) {
            // admin / admin123，角色 admin
            let adminHash = hashPassword("admin123", "qz2026", 1000)
            db.exec("INSERT INTO users VALUES (1, 'admin', '${adminHash}', 1)")
            // user / user123，角色 user
            let userHash = hashPassword("user123", "qz2026", 1000)
            db.exec("INSERT INTO users VALUES (2, 'user', '${userHash}', 2)")
        }
    }

    /* 按用户名查用户，不存在返回 None。 */
    public func findUserByUsername(username: String): ?UserRow {
        let rs = db.query("SELECT * FROM users WHERE username = '${username}'")
        if (rs.rowCount() == 0) {
            return None
        }
        return Some(toUserRow(rs.rows.get(0).getOrThrow()))
    }

    /* 按 id 查用户，不存在返回 None。 */
    public func findUserById(id: Int64): ?UserRow {
        let rs = db.query("SELECT * FROM users WHERE id = ${id}")
        if (rs.rowCount() == 0) {
            return None
        }
        return Some(toUserRow(rs.rows.get(0).getOrThrow()))
    }

    public func listUsers(): ArrayList<UserRow> {
        let rs = db.query("SELECT * FROM users ORDER BY id")
        let out = ArrayList<UserRow>()
        for (row in rs.rows) {
            out.add(toUserRow(row))
        }
        return out
    }

    public func createUser(username: String, passwordHash: String, roleId: Int64): Int64 {
        let id = nextUserId()
        db.exec("INSERT INTO users VALUES (${id}, '${username}', '${passwordHash}', ${roleId})")
        return id
    }

    public func deleteUser(id: Int64): Bool {
        return db.exec("DELETE FROM users WHERE id = ${id}") > 0
    }

    public func listRoles(): ArrayList<RoleRow> {
        let rs = db.query("SELECT * FROM roles ORDER BY id")
        let out = ArrayList<RoleRow>()
        for (row in rs.rows) {
            out.add(RoleRow(
                Int64.parse(valueStr(row.get(0).getOrThrow())),
                valueStr(row.get(1).getOrThrow())
            ))
        }
        return out
    }

    public func listPermissions(): ArrayList<PermRow> {
        let rs = db.query("SELECT * FROM permissions ORDER BY id")
        let out = ArrayList<PermRow>()
        for (row in rs.rows) {
            out.add(PermRow(
                Int64.parse(valueStr(row.get(0).getOrThrow())),
                valueStr(row.get(1).getOrThrow()),
                valueStr(row.get(2).getOrThrow())
            ))
        }
        return out
    }

    /* 角色名（id -> name），不存在返回空串。 */
    public func roleNameOf(roleId: Int64): String {
        let rs = db.query("SELECT * FROM roles WHERE id = ${roleId}")
        if (rs.rowCount() == 0) {
            return ""
        }
        return valueStr(rs.rows.get(0).getOrThrow().get(1).getOrThrow())
    }

    /* 用户拥有的权限码集合：用户 -> 角色 -> 权限，分步查询 + 应用层组合。 */
    public func permissionCodesOf(userId: Int64): ArrayList<String> {
        let out = ArrayList<String>()
        let rs1 = db.query("SELECT * FROM users WHERE id = ${userId}")
        if (rs1.rowCount() == 0) {
            return out
        }
        let roleId = Int64.parse(valueStr(rs1.rows.get(0).getOrThrow().get(3).getOrThrow()))
        let rs2 = db.query("SELECT * FROM role_permissions WHERE role_id = ${roleId}")
        for (row in rs2.rows) {
            let pid = Int64.parse(valueStr(row.get(1).getOrThrow()))
            let rs3 = db.query("SELECT * FROM permissions WHERE id = ${pid}")
            if (rs3.rowCount() > 0) {
                out.add(valueStr(rs3.rows.get(0).getOrThrow().get(1).getOrThrow()))
            }
        }
        return out
    }

    public func hasPermission(userId: Int64, code: String): Bool {
        let codes = permissionCodesOf(userId)
        for (c in codes) {
            if (c == code) {
                return true
            }
        }
        return false
    }

    public func close(): Unit {
        db.close()
    }

    /* ---------- internals ---------- */

    private func toUserRow(row: ArrayList<DbValue>): UserRow {
        return UserRow(
            Int64.parse(valueStr(row.get(0).getOrThrow())),
            valueStr(row.get(1).getOrThrow()),
            valueStr(row.get(2).getOrThrow()),
            Int64.parse(valueStr(row.get(3).getOrThrow()))
        )
    }

    private func nextUserId(): Int64 {
        let rs = db.query("SELECT * FROM users ORDER BY id DESC")
        if (rs.rowCount() == 0) {
            return 1
        }
        return Int64.parse(valueStr(rs.rows.get(0).getOrThrow().get(0).getOrThrow())) + 1
    }
}
