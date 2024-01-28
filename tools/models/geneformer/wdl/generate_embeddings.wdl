version development

workflow scatter_generate_embeddings {
    input {
        Array[Directory] dataset_shards
        Directory model
        String output_uri
        Int? emb_layer

        String s3_region = "us-west-2"
        String docker
    }

    # work around any tooling that might try to verify pre-existence of the output URI when
    # launching the workflow:
    String output_uri2 = sub(output_uri, "s3_//", "s3://")

    # create the output TileDB array
    call init_embeddings_array {
        input:
        uri = output_uri2, s3_region, docker
    }

    # generate each shard's embeddings and write them into the above-created array
    scatter (shard in dataset_shards) {
        call generate_embeddings after init_embeddings_array {
            input:
            dataset = shard, output_uri = output_uri2, model, emb_layer, s3_region, docker
        }
    }

    output {}
}

task init_embeddings_array {
    input {
        String uri
        String s3_region
        String docker

        Int embedding_dim = 512 # TODO: avoid hard-coding this
    }

    command <<<
        set -euo pipefail
        # use venv with pinned, older tiledbsoma/tiledb to ensure compatibility with
        # Census embeddings curator
        source /census-geneformer/embeddings_tiledbsoma_venv/bin/activate
        python3 - <<'EOF'
        import tiledb
        import tiledbsoma
        import pyarrow as pa
        tiledbsoma.SparseNDArray.create(
            '~{uri}',
            type=pa.float32(),
            shape=(2**31-2, ~{embedding_dim}),
            context = tiledbsoma.options.SOMATileDBContext(
                tiledb_ctx=tiledb.Ctx({"vfs.s3.region": '~{s3_region}'})
            )
        ).close()
        EOF
    >>>

    runtime {
        docker: docker
    }

    output {}
}

task generate_embeddings {
    input {
        Directory dataset
        Directory model
        String output_uri
        String s3_region

        Int emb_layer = -1  # -1 or 0

        String docker
    }

    command <<<
        set -euo pipefail
        >&2 sha256sum /census-geneformer/*.py
        source /census-geneformer/embeddings_tiledbsoma_venv/bin/activate
        mkdir hf
        export HF_HOME="$(pwd)/hf"
        export TMPDIR="$HF_HOME"
        export AWS_DEFAULT_REGION='~{s3_region}'
        export TQDM_MININTERVAL=10
        python3 /census-geneformer/generate-geneformer-embeddings.py \
            --emb-layer ~{emb_layer} --batch-size 10 --tiledbsoma \
            '~{model}' '~{dataset}' '~{output_uri}'
    >>>

    runtime {
        # sizing to g5.2xlarge since EmbExtractor uses only one GPU
        cpu: 8
        memory: "30G"
        gpu: true
        acceleratorCount: 1
        acceleratorType: "nvidia-tesla-a10g"
        docker: docker
        # for robustness to sporadic errors e.g.
        # https://github.com/pytorch/pytorch/issues/21819
        maxRetries: 1
    }

    output {}
}
