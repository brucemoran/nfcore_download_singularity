#!/usr/bin/env nextflow

def helpMessage() {
  log.info"""
  -----------------------------------------------------------------------
  !!!      DOWNLOAD SINGULARITY CONTAINERS FOR NF-CORE PIPELINES      !!!
  -----------------------------------------------------------------------
  Usage:

  nextflow run brucemoran/nfcore_download_singularity

  Mandatory arguments:

    --outdir        [str]       Path to write output

    --pipeline      [str]       Name of nf-core pipeline as per `nf-core list`

    --revision      [str]       Revision of nf-core pipeline to use

    --nxf_singu_cache      [str]       Path to \$NXF_SINGULARITY_CACHE

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
  for mains in \$(find ${workflow}/modules -name main.nf ); do
    outname=\$(echo \${mains} | perl -ane '@s=split(/\\//); if(@s == 4){print \$s[-2];} if(@s == 5){print \$s[-2];} if(@s == 6){print \$s[-3] . "_" . \$s[-2];}' | sed 's#/#.#g').singu
    grep -A2 ${spd} \${mains} | cut -d\\' -f2 | tail -n2 > \$outname
    if [[ \$(grep "depot.galaxyproject" \${mains} | wc -l) == 0 ]]; then
      echo "docker://"\$(grep 'container \\"' \${mains} | cut -d\\" -f2) > \$outname
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
  file("*.{sif,img}") into sing_dls
  file("command.txt") into sing_com

  script:
  spd = "singularity_pull_docker_container"
  """
  if [[ \$(grep "depot.galaxyproject" ${mains} | wc -l) > 0 ]]; then
    echo "wget -O "depot.galaxyproject.org-singularity-"\$(basename \$(grep "depot.galaxyproject" ${mains}) | sed 's/\\:/-/')".img" \$(grep "depot.galaxyproject" ${mains})" > command.txt
    wget -O "depot.galaxyproject.org-singularity-"\$(basename \$(grep "depot.galaxyproject" ${mains}) | sed 's/\\:/-/')".img" \$(grep "depot.galaxyproject" ${mains})
  else
    if [[ \$(cat ${mains}) != "docker://" ]]; then
      NAME=echo \$(\$(cat ${mains} | sed 's#docker://##' | sed 's#[/:;]#-#g')".img")
      echo "singularity pull --name \$NAME \$(cat ${mains})" > command.txt
      singularity pull --name \$NAME \$(cat ${mains})
    else
      touch fake.sif
      touch command.txt
    fi
  fi
  """
}

// 4.19: tar for sending on sendmail
process zipup {

    label 'low_mem'
    publishDir "${params.outDir}", mode: 'copy'

    input:
    file(comms) from sing_com.collect()

    output:
    file("singularity_commands.txt") into send_com

    script:
    """
    for x in \$(ls); do
      cat \$x
    done >> singularity_commands.txt
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
  def attachments = send_com.toList().getVal()

  sendMail(to: "${params.email}",
           subject: subject,
           body: msg,
           attach: attachments)
}
