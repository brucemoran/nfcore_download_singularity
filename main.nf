#!/usr/bin/env nextflow

def helpMessage() {
  log.info"""
  -----------------------------------------------------------------------
                          TUMOUR_ONLY PIPELINE
  -----------------------------------------------------------------------
  Usage:

  nextflow run brucemoran/tumour_only

  Mandatory arguments:

    --outdir        [str]       Path to write output

    --pipeline      [str]       Name of nf-core pipeline as per `nf-core list`

    --revision      [str]       Revision of nf-core pipeline to use

    --email         [str]       Email address to send reports
    """.stripIndent()
}

if (params.help) exit 0, helpMessage()

if(!params.outdir){
    exit 1, "Please include --outdir path for writing to"
}

if(!params.pipeline){
    exit 1, "Please include --pipeline specifying the nf-core pipeline you want"
}

if(!params.revision){
    exit 1, "Please include --revision of the nf-core pipeline you want"
}

if(!params.email){
    exit 1, "Please include --email your@email.com"
}

/*
================================================================================
                          -0. nf-core download
================================================================================
*/
/* 0.00: Download pipeline so we have files to interogate
*/
Channel
  .from(params.pipeline)
  .set { pipe_in }

process Nfcore_download {

  publishDir "${params.outdir}/${params.pipeline}/${params.revision}/", mode: "copy"

  input:
  val(pipeline) from pipe_in

  output:
  tuple val(pipeline), file("configs"), file("workflow") into sing_pull

  script:
  """
  nf-core download ${pipeline} -r ${params.revision} -o output -c none
  mv output/configs configs/
  mv output/workflow workflow/
  rm -rf output
  """
}

/*
================================================================================
                          0. Parse modules for Singularity
================================================================================
*/

process Singu_parse {

  input:
  tuple val(pipeline), file(configs), file(workflow) from sing_pull

  output:
  file("*.singu") into sing_got

  script:
  spd = "singularity_pull_docker_container"
  """
  for mains in \$(find workflow/modules -name main.nf ); do
    outname=$(echo ${mains} | perl -ane '@s=split(/\\//);
      if(@s == 4){print \$s[-2];}
      if(@s == 5){print \$s[-2];}
      if(@s == 6){print \$s[-3] . "_" . \$s[-2];}' | sed 's#/#.#g').singu
    grep -A2 ${spd} ${mains} | cut -d\\' -f2 | tail -n2 > rpt/\$outname
    if [[ \$(grep "depot.galaxyproject" ${mains} | wc -l) == 0 ]]; then
      echo "docker://"\$(grep 'container \\"' ${mains} | cut -d\\" -f2) > rpt/\$outname
    fi
  done
  """
}

/*
================================================================================
                          0. Download Singularity
================================================================================
*/

sing_flat = sing_got.flatten()

process Singu_dl {

  publishDir "${params.outdir}/${params.pipeline}/${params.revision}/singularity-images/", mode: "copy", pattern: "*.{img,sif}"

  input:
  file(mains) from sing_flat

  output:
  file("*") into sing_dls

  script:
  spd = "singularity_pull_docker_container"
  """
  if [[ \$(grep "depot.galaxyproject" ${mains} | wc -l) > 0 ]]; then
    wget -O "depot.galaxyproject.org-singularity-"\$(basename \$(grep "depot.galaxyproject" ${mains}) | sed 's/\\:/-/')".img" \$(grep "depot.galaxyproject" ${mains})
  else
    if [[ \$(cat ${mains}) != "docker://" ]]; then
      singularity pull \$(cat ${mains})
    else
      touch fake.sif
    fi
  fi
  """
}

workflow.onComplete {
  sleep(1000)
  def subject = """\
    [brucemoran/nfcore_download_singularity] SUCCESS [$workflow.runName]
    """
    .stripIndent()
  if (!workflow.success) {
      subject = """\
        [brucemoran/nfcore_download_singularity] FAILURE [$workflow.runName]
        """
        .stripIndent()
  }

  def msg = """\
    Pipeline execution summary
    ---------------------------
    RunName     : ${workflow.runName}
    Completed at: ${workflow.complete}
    Duration    : ${workflow.duration}
    workDir     : ${workflow.workDir}
    exit status : ${workflow.exitStatus}
    """
    .stripIndent()

  sendMail(to: "${params.email}",
           subject: subject,
           body: msg)
}
