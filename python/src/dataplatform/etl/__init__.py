"""ETL building blocks for the medallion lakehouse.

``transforms`` and ``aggregations`` hold pure ``DataFrame -> DataFrame`` functions that are
unit tested in isolation. The ``*_to_*`` modules compose them with reads and Delta writes.
"""
