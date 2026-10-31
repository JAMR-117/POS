import 'package:flutter/material.dart';

/// Lista maestra oficial de departamentos físicos estandarizados para Cerrajería y Electrónica Automotriz.
const List<String> kPhysicalDepartments = [
  'Residencial',
  'Automotriz',
  'Seguridad / Punto',
  'Motos',
  'Pilas y Baterías',
  'Transponders y Chips',
  'Controles y Carcasas',
  'Cerraduras y Candados',
  'Herramientas y Accesorios',
];

/// Lista maestra completa de departamentos del sistema (incluyendo Servicios).
const List<String> kAllStandardDepartments = [
  ...kPhysicalDepartments,
  'Servicios',
];

class DepartmentStyle {
  final Color fg;
  final Color bg;
  final Color border;
  final IconData icon;

  const DepartmentStyle({
    required this.fg,
    required this.bg,
    required this.border,
    required this.icon,
  });

  static DepartmentStyle of(String rawDept) {
    final dep = rawDept.trim().toLowerCase();

    if (dep.contains('automotriz')) {
      return DepartmentStyle(
        fg: const Color(0xFF0D47A1),
        bg: const Color(0xFFE3F2FD),
        border: Colors.blue.shade300,
        icon: Icons.directions_car_outlined,
      );
    }
    if (dep.contains('residencial')) {
      return DepartmentStyle(
        fg: const Color(0xFF1B5E20),
        bg: const Color(0xFFE8F5E9),
        border: Colors.green.shade300,
        icon: Icons.home_outlined,
      );
    }
    if (dep.contains('seguridad') || dep.contains('punto')) {
      return DepartmentStyle(
        fg: const Color(0xFF6A1B9A),
        bg: const Color(0xFFF3E5F5),
        border: Colors.purple.shade300,
        icon: Icons.shield_outlined,
      );
    }
    if (dep.contains('moto')) {
      return DepartmentStyle(
        fg: const Color(0xFFE65100),
        bg: const Color(0xFFFFF8E1),
        border: Colors.amber.shade600,
        icon: Icons.two_wheeler_outlined,
      );
    }
    if (dep.contains('servicio')) {
      return DepartmentStyle(
        fg: const Color(0xFF006064),
        bg: const Color(0xFFE0F7FA),
        border: Colors.cyan.shade400,
        icon: Icons.handyman_outlined,
      );
    }
    if (dep.contains('pila') || dep.contains('bateria') || dep.contains('batería')) {
      return DepartmentStyle(
        fg: const Color(0xFFE65100),
        bg: const Color(0xFFFFF3E0),
        border: Colors.orange.shade400,
        icon: Icons.battery_charging_full,
      );
    }
    if (dep.contains('transponder') || dep.contains('chip')) {
      return DepartmentStyle(
        fg: const Color(0xFF283593),
        bg: const Color(0xFFE8EAF6),
        border: Colors.indigo.shade300,
        icon: Icons.memory_outlined,
      );
    }
    if (dep.contains('control') || dep.contains('carcasa')) {
      return DepartmentStyle(
        fg: const Color(0xFFBF360C),
        bg: const Color(0xFFFBE9E7),
        border: Colors.deepOrange.shade300,
        icon: Icons.settings_remote_outlined,
      );
    }
    if (dep.contains('cerradura') || dep.contains('candado')) {
      return DepartmentStyle(
        fg: const Color(0xFF4E342E),
        bg: const Color(0xFFEFEBE9),
        border: Colors.brown.shade300,
        icon: Icons.lock_outline,
      );
    }
    if (dep.contains('herramienta') || dep.contains('accesorio')) {
      return DepartmentStyle(
        fg: const Color(0xFF37474F),
        bg: const Color(0xFFECEFF1),
        border: Colors.blueGrey.shade300,
        icon: Icons.construction_outlined,
      );
    }

    return DepartmentStyle(
      fg: const Color(0xFF455A64),
      bg: const Color(0xFFF5F5F5),
      border: Colors.grey.shade400,
      icon: Icons.category_outlined,
    );
  }
}

/// Badge visual estandarizado para mostrar el Departamento en Inventario, F1 y Búsqueda Rápida.
class DepartmentBadge extends StatelessWidget {
  final String departamento;
  final bool compact;
  final VoidCallback? onTap;

  const DepartmentBadge({
    super.key,
    required this.departamento,
    this.compact = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = departamento.trim().isEmpty ? 'Residencial' : departamento.trim();
    final style = DepartmentStyle.of(label);

    final badge = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: style.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: compact ? 11 : 13, color: style.fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: compact ? 10.5 : 11.5,
                fontWeight: FontWeight.bold,
                color: style.fg,
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return badge;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: badge,
    );
  }
}
