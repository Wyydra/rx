window.BENCHMARK_DATA = {
  "lastUpdate": 1772483195022,
  "repoUrl": "https://github.com/Wyydra/rx",
  "entries": {
    "Benchmark": [
      {
        "commit": {
          "author": {
            "email": "paulchopinet@gmail.com",
            "name": "Wyydra",
            "username": "Wyydra"
          },
          "committer": {
            "email": "paulchopinet@gmail.com",
            "name": "Wyydra",
            "username": "Wyydra"
          },
          "distinct": true,
          "id": "71c16412f59713e75f2d30302be00bd59e42d675",
          "message": "ci",
          "timestamp": "2026-03-01T23:45:29+01:00",
          "tree_id": "f00fdac46502357bab200faa11c6dc054bd23470",
          "url": "https://github.com/Wyydra/rx/commit/71c16412f59713e75f2d30302be00bd59e42d675"
        },
        "date": 1772405210747,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "ackermann/lua",
            "value": 17.2569,
            "unit": "ms",
            "extra": "mean=17.2493ms σ=0.3154ms n=50"
          },
          {
            "name": "ackermann/py",
            "value": 129.887,
            "unit": "ms",
            "extra": "mean=129.9558ms σ=2.5847ms n=50"
          },
          {
            "name": "ackermann/rxt",
            "value": 24.4605,
            "unit": "ms",
            "extra": "mean=24.5271ms σ=0.2815ms n=50"
          },
          {
            "name": "fib/lua",
            "value": 54.552,
            "unit": "ms",
            "extra": "mean=54.6527ms σ=0.5371ms n=50"
          },
          {
            "name": "fib/py",
            "value": 117.0844,
            "unit": "ms",
            "extra": "mean=117.853ms σ=1.6785ms n=50"
          },
          {
            "name": "fib/rxt",
            "value": 86.5711,
            "unit": "ms",
            "extra": "mean=87.2755ms σ=3.524ms n=50"
          },
          {
            "name": "greet/lua",
            "value": 1.1186,
            "unit": "ms",
            "extra": "mean=1.1359ms σ=0.0466ms n=50"
          },
          {
            "name": "greet/py",
            "value": 11.4037,
            "unit": "ms",
            "extra": "mean=11.425ms σ=0.1081ms n=50"
          },
          {
            "name": "greet/rxt",
            "value": 0.4908,
            "unit": "ms",
            "extra": "mean=0.5117ms σ=0.0645ms n=50"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "paulchopinet@gmail.com",
            "name": "Wyydra",
            "username": "Wyydra"
          },
          "committer": {
            "email": "paulchopinet@gmail.com",
            "name": "Wyydra",
            "username": "Wyydra"
          },
          "distinct": true,
          "id": "a6a9a8f0a970bfb8e5be7184fc3a60f05347fa3e",
          "message": "ci",
          "timestamp": "2026-03-02T18:38:09+01:00",
          "tree_id": "e0d702826d68dfafbfa74ac9764fabf23239b203",
          "url": "https://github.com/Wyydra/rx/commit/a6a9a8f0a970bfb8e5be7184fc3a60f05347fa3e"
        },
        "date": 1772473163049,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "ackermann/rxt",
            "value": 24.2413,
            "unit": "ms",
            "extra": "mean=24.5012ms σ=0.9552ms n=50"
          },
          {
            "name": "fib/rxt",
            "value": 86.5879,
            "unit": "ms",
            "extra": "mean=87.1067ms σ=1.4083ms n=50"
          },
          {
            "name": "greet/rxt",
            "value": 0.4875,
            "unit": "ms",
            "extra": "mean=0.4944ms σ=0.0311ms n=50"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "paulchopinet@gmail.com",
            "name": "Wyydra",
            "username": "Wyydra"
          },
          "committer": {
            "email": "paulchopinet@gmail.com",
            "name": "Wyydra",
            "username": "Wyydra"
          },
          "distinct": true,
          "id": "bc764ef9b4279b72e6f17e74e9756214319ccab7",
          "message": "rxt v2",
          "timestamp": "2026-03-02T20:14:45+01:00",
          "tree_id": "f1fd720dbf30645c4dac71642e1bcfdad750ce10",
          "url": "https://github.com/Wyydra/rx/commit/bc764ef9b4279b72e6f17e74e9756214319ccab7"
        },
        "date": 1772478979695,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "ackermann/rxt",
            "value": 19.386,
            "unit": "ms",
            "extra": "mean=19.814ms σ=1.2544ms n=50"
          },
          {
            "name": "fib/rxt",
            "value": 79.2114,
            "unit": "ms",
            "extra": "mean=78.6342ms σ=2.8473ms n=50"
          },
          {
            "name": "greet/rxt",
            "value": 0.2792,
            "unit": "ms",
            "extra": "mean=0.3037ms σ=0.0699ms n=50"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "paulchopinet@gmail.com",
            "name": "Wyydra",
            "username": "Wyydra"
          },
          "committer": {
            "email": "paulchopinet@gmail.com",
            "name": "Wyydra",
            "username": "Wyydra"
          },
          "distinct": true,
          "id": "3b74da2e2c45cc48b96227dbbf6c9613b161d6fe",
          "message": "fix gc dead callframe check",
          "timestamp": "2026-03-02T21:24:51+01:00",
          "tree_id": "e202dc1835562561c974e17a03c408ddb9c11d52",
          "url": "https://github.com/Wyydra/rx/commit/3b74da2e2c45cc48b96227dbbf6c9613b161d6fe"
        },
        "date": 1772483194432,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "ackermann/rxt",
            "value": 24.7314,
            "unit": "ms",
            "extra": "mean=24.8054ms σ=0.3148ms n=50"
          },
          {
            "name": "fib/rxt",
            "value": 89.084,
            "unit": "ms",
            "extra": "mean=89.6829ms σ=1.6619ms n=50"
          },
          {
            "name": "greet/rxt",
            "value": 0.4793,
            "unit": "ms",
            "extra": "mean=0.5045ms σ=0.0578ms n=50"
          }
        ]
      }
    ]
  }
}